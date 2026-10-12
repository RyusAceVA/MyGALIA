import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:mygalia/core/lifecycle/refresh_signals.dart';
import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/core/storage/cache_store.dart';
import 'package:mygalia/features/schedule/domain/course.dart';
import 'package:mygalia/features/schedule/presentation/schedule_controller.dart';

import '../support/hive_test_utils.dart';
import '../support/state_waiter.dart';
import '../support/test_env.dart';

/// Contrôleur dont l'horloge est pilotée par le test.
class _ClockedScheduleController extends ScheduleController {
  _ClockedScheduleController(this.clock);

  final DateTime Function() clock;

  @override
  DateTime now() => clock();
}

void main() {
  late TestEnv env;
  late Box<dynamic> box;
  late DateTime fakeNow;
  final DateTime monday = DateTime(2026, 10, 12);
  final provider = scheduleControllerProvider(monday);

  setUp(() async {
    fakeNow = DateTime.now();
    box = await openTestBox();
    env = await TestEnv.start(
      overrides: [
        cacheStoreProvider.overrideWithValue(CacheStore(box)),
        scheduleControllerProvider
            .overrideWith(() => _ClockedScheduleController(() => fakeNow)),
      ],
    );
    await env.storeCredentials();
    env.container.listen(provider, (_, __) {});
  });

  tearDown(() async {
    await env.dispose();
    await deleteTestBox(box);
  });

  Future<void> signal(RefreshReason reason) async {
    env.container.read(refreshSignalsProvider).emit(reason);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  Future<DataState<WeekSchedule>> settled() => waitForState(
        env.container,
        provider,
        (DataState<WeekSchedule> s) => s is! DataLoading<WeekSchedule> && !s.isRefreshing,
      );

  test('données récentes : retour du réseau sans requête', () async {
    await settled();
    final int before = env.server.planningCalls;

    await signal(RefreshReason.networkBack);

    expect(env.server.planningCalls, before);
  });

  test('données anciennes : retour au premier plan = rechargement', () async {
    await settled();
    final int before = env.server.planningCalls;
    fakeNow = fakeNow.add(const Duration(minutes: 31));

    await signal(RefreshReason.resumed);
    final DataState<WeekSchedule> state = await settled();

    expect(env.server.planningCalls - before, 5);
    expect(state, isA<DataSuccess<WeekSchedule>>());
  });

  test('dernier essai en échec : retour du réseau = rechargement immédiat', () async {
    env.server.planningBodyOverride = 'corrompu';
    expect(await settled(), isA<DataError<WeekSchedule>>());
    env.server.planningBodyOverride = null;

    await signal(RefreshReason.networkBack);

    expect(await settled(), isA<DataSuccess<WeekSchedule>>());
  });

  test('anti-rafale : un seul rechargement auto par fenêtre de 20 s', () async {
    env.server.planningBodyOverride = 'corrompu';
    await settled();
    final int before = env.server.planningCalls;

    // Un rechargement sur page corrompue = 2 requêtes (essai + rejeu après
    // reconnexion, la page n'ayant pas de repère de données).
    await signal(RefreshReason.networkBack);
    await settled();
    await signal(RefreshReason.networkBack);
    await settled();
    expect(env.server.planningCalls - before, 2, reason: 'second signal ignoré');

    fakeNow = fakeNow.add(const Duration(seconds: 21));
    await signal(RefreshReason.networkBack);
    await settled();
    expect(env.server.planningCalls - before, 4);
  });
}
