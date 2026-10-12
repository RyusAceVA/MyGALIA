import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/core/storage/cache_store.dart';
import 'package:mygalia/features/schedule/data/schedule_repository.dart';
import 'package:mygalia/features/schedule/domain/course.dart';
import 'package:mygalia/features/schedule/presentation/schedule_controller.dart';

import '../support/hive_test_utils.dart';
import '../support/state_waiter.dart';
import '../support/test_env.dart';

void main() {
  late TestEnv env;
  late Box<dynamic> box;
  final DateTime monday = DateTime(2026, 10, 12);
  final provider = scheduleControllerProvider(monday);

  setUp(() async {
    box = await openTestBox();
    env = await TestEnv.start(
      overrides: [cacheStoreProvider.overrideWithValue(CacheStore(box))],
    );
    await env.storeCredentials();
  });

  tearDown(() async {
    await env.dispose();
    await deleteTestBox(box);
  });

  /// Garde le provider (autoDispose) en vie pendant le test.
  ProviderSubscription<DataState<WeekSchedule>> keepAlive() =>
      env.container.listen(provider, (_, __) {});

  test('ouverture sans cache : Chargement puis Succès', () async {
    keepAlive();
    expect(env.container.read(provider), isA<DataLoading<WeekSchedule>>());

    final DataState<WeekSchedule> state = await waitForState(
      env.container,
      provider,
      (DataState<WeekSchedule> s) => s is DataSuccess<WeekSchedule>,
    );

    expect(state.data?.courses, hasLength(5));
    expect(env.server.planningCalls, 5);
  });

  test('Réessayer après une erreur déclenche bien un nouvel appel réseau', () async {
    env.server.planningServerErrors = 3; // essai + 2 relances : tout échoue
    keepAlive();
    final DataState<WeekSchedule> failed = await waitForState(
      env.container,
      provider,
      (DataState<WeekSchedule> s) => s is DataError<WeekSchedule>,
    );
    expect(failed.failure, isA<ServerFailure>());
    final int callsAfterError = env.server.planningCalls;

    await env.container.read(provider.notifier).refresh();

    expect(env.server.planningCalls, greaterThan(callsAfterError));
    expect(env.container.read(provider), isA<DataSuccess<WeekSchedule>>());
  });

  test('deux appuis pendant un chargement : une seule requête réseau', () async {
    keepAlive();
    await waitForState(
      env.container,
      provider,
      (DataState<WeekSchedule> s) => s is DataSuccess<WeekSchedule>,
    );
    final ScheduleController controller = env.container.read(provider.notifier);
    final int before = env.server.planningCalls;

    final Future<void> first = controller.refresh();
    final Future<void> second = controller.refresh();
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);

    expect(env.server.planningCalls - before, 5, reason: 'une seule semaine chargée');
  });

  test('rafraîchissement raté : données en cache conservées + avertissement', () async {
    keepAlive();
    await waitForState(
      env.container,
      provider,
      (DataState<WeekSchedule> s) => s is DataSuccess<WeekSchedule>,
    );
    env.server.planningBodyOverride = 'corrompu';

    await env.container.read(provider.notifier).refresh();

    final DataState<WeekSchedule> state = env.container.read(provider);
    expect(state, isA<DataCached<WeekSchedule>>());
    expect(state.failure, isA<DataFailure>());
    expect(state.data?.courses, hasLength(5));
  });

  test('cache récent : affiché sans requête ; Réessayer interroge le réseau', () async {
    await env.container.read(scheduleRepositoryProvider).fetchWeek(monday);
    final int before = env.server.planningCalls;

    keepAlive();
    final DataState<WeekSchedule> initial = env.container.read(provider);
    expect(initial, isA<DataCached<WeekSchedule>>());
    expect(initial.isRefreshing, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(env.server.planningCalls, before, reason: 'pas de requête à l\'ouverture');

    await env.container.read(provider.notifier).refresh();
    expect(env.server.planningCalls - before, 5);
    expect(env.container.read(provider), isA<DataSuccess<WeekSchedule>>());
  });

  test('erreur : un nouvel appui repart de zéro (aucun état bloqué)', () async {
    env.server.planningBodyOverride = 'corrompu';
    keepAlive();
    await waitForState(
      env.container,
      provider,
      (DataState<WeekSchedule> s) => s is DataError<WeekSchedule>,
    );

    for (int i = 0; i < 3; i++) {
      final int before = env.server.planningCalls;
      await env.container.read(provider.notifier).refresh();
      expect(env.server.planningCalls, greaterThan(before), reason: 'appui n°${i + 1}');
      expect(env.container.read(provider), isA<DataError<WeekSchedule>>());
    }
  });
}
