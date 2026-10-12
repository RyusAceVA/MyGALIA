// Phase 3 — scénarios de vérification du cahier des charges, de bout en bout :
// contrôleur d'écran → repository → SchoolClient/SessionManager → réseau
// (faux serveur SC Form local, équivalent de MockWebServer).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/core/storage/cache_store.dart';
import 'package:mygalia/features/auth/presentation/auth_controller.dart';
import 'package:mygalia/features/grades/domain/grade.dart';
import 'package:mygalia/features/grades/presentation/grades_controller.dart';
import 'package:mygalia/features/schedule/domain/course.dart';
import 'package:mygalia/features/schedule/presentation/schedule_controller.dart';

import '../support/fake_scform_server.dart';
import '../support/hive_test_utils.dart';
import '../support/state_waiter.dart';
import '../support/test_env.dart';

void main() {
  late TestEnv env;
  late Box<dynamic> box;
  final DateTime monday = DateTime(2026, 10, 12);
  final schedule = scheduleControllerProvider(monday);
  final grades = gradesControllerProvider('');

  setUp(() async {
    box = await openTestBox();
    env = await TestEnv.start(
      // Délai de réception court : le scénario « timeout » reste rapide.
      receiveTimeout: const Duration(milliseconds: 500),
      overrides: [cacheStoreProvider.overrideWithValue(CacheStore(box))],
    );
    await env.storeCredentials();
    env.container
      ..listen(authControllerProvider, (_, __) {})
      ..listen(schedule, (_, __) {});
  });

  tearDown(() async {
    await env.dispose();
    await deleteTestBox(box);
  });

  Future<DataState<T>> settled<T>(ProviderListenable<DataState<T>> provider) =>
      waitForState(
        env.container,
        provider,
        (DataState<T> s) => s is! DataLoading<T> && !s.isRefreshing,
      );

  Future<DataState<WeekSchedule>> refreshSchedule() async {
    await env.container.read(schedule.notifier).refresh();
    return env.container.read(schedule);
  }

  for (final (String name, ExpiryMode mode) in [
    ('1. session expirée renvoyée en 200 avec la page de login', ExpiryMode.loginPage200),
    ('2. session expirée renvoyée en 302', ExpiryMode.redirect302),
    ('3. session expirée renvoyée en 401', ExpiryMode.unauthorized401),
  ]) {
    test('$name : reconnexion silencieuse, rejeu, données affichées', () async {
      expect(await settled(schedule), isA<DataSuccess<WeekSchedule>>());
      env.server
        ..expiryMode = mode
        ..expireSchoolSession();

      final DataState<WeekSchedule> state = await refreshSchedule();

      expect(state, isA<DataSuccess<WeekSchedule>>());
      expect(state.data?.courses, hasLength(5));
      expect(env.sessions.renewalCount, 2, reason: 'une seule reconnexion');
      expect(env.container.read(authControllerProvider), isNot(isA<AuthSignedOut>()));
    });
  }

  test('4. deux requêtes parallèles sur une session expirée : une seule reconnexion', () async {
    env.container.listen(grades, (_, __) {});
    await settled(schedule);
    await settled(grades);
    env.server
      ..expireSchoolSession()
      ..getTokenDelay = const Duration(milliseconds: 200);
    final int getTokens = env.server.getTokenCalls;

    await Future.wait([
      env.container.read(schedule.notifier).refresh(),
      env.container.read(grades.notifier).refresh(),
    ]);

    expect(env.container.read(schedule), isA<DataSuccess<WeekSchedule>>());
    expect(env.container.read(grades), isA<DataSuccess<GradesSnapshot>>());
    expect(env.sessions.renewalCount, 2);
    expect(env.server.getTokenCalls - getTokens, 1);
  });

  test('5. reconnexion refusée : écran de connexion avec message, aucune relance', () async {
    await settled(schedule);
    env.server
      ..password = 'mot-de-passe-change'
      ..expireApiTokens()
      ..expireSchoolSession();
    final int logins = env.server.loginCalls;

    final DataState<WeekSchedule> state = await refreshSchedule();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(state.failure, isA<InvalidCredentialsFailure>());
    expect(env.server.loginCalls - logins, 1, reason: 'jamais relancé automatiquement');
    final AuthState auth = env.container.read(authControllerProvider);
    expect(auth, isA<AuthSignedOut>());
    expect((auth as AuthSignedOut).message, isNotEmpty);
    expect(await env.vault.readCredentials(), isNull);
  });

  test('6. un timeout suivi d\'un succès : relance automatique transparente', () async {
    await settled(schedule);
    env.server
      ..planningDelay = const Duration(milliseconds: 1500)
      ..planningDelayCount = 1;
    final int before = env.server.planningCalls;

    final DataState<WeekSchedule> state = await refreshSchedule();

    expect(state, isA<DataSuccess<WeekSchedule>>());
    expect(env.server.planningCalls - before, 6, reason: '5 jours + 1 relance');
  });

  test('7. réponse vide ou corrompue : erreur typée, jamais mise en cache', () async {
    final ProviderContainer container = env.container;
    for (final String body in ['', 'contenu corrompu {"oops"}']) {
      await box.clear();
      env.server.planningBodyOverride = body;

      final DataState<WeekSchedule> state = await refreshSchedule();

      expect(state, isA<DataError<WeekSchedule>>(), reason: 'corps « $body »');
      expect(state.failure, isA<DataFailure>());
      expect(box.isEmpty, isTrue, reason: 'rien en cache pour « $body »');
      expect(container.read(schedule).data, isNull);
    }
  });

  test('8. Réessayer après une erreur déclenche bien un nouvel appel réseau', () async {
    env.server.planningServerErrors = 3;
    expect(await settled(schedule), isA<DataError<WeekSchedule>>());
    final int before = env.server.planningCalls;

    final DataState<WeekSchedule> state = await refreshSchedule();

    expect(env.server.planningCalls, greaterThan(before));
    expect(state, isA<DataSuccess<WeekSchedule>>());
  });
}
