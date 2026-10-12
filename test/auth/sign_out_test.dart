import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/storage/cache_store.dart';
import 'package:mygalia/features/auth/presentation/auth_controller.dart';
import 'package:mygalia/features/grades/data/grades_repository.dart';
import 'package:mygalia/features/schedule/data/schedule_repository.dart';

import '../support/hive_test_utils.dart';
import '../support/test_env.dart';

void main() {
  late TestEnv env;
  late Box<dynamic> box;
  late AuthController auth;
  final DateTime monday = DateTime(2026, 10, 12);

  setUp(() async {
    box = await openTestBox();
    env = await TestEnv.start(
      overrides: [cacheStoreProvider.overrideWithValue(CacheStore(box))],
    );
    env.container.listen(authControllerProvider, (_, __) {});
    auth = env.container.read(authControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero); // lecture initiale du coffre
  });

  tearDown(() async {
    await env.dispose();
    await deleteTestBox(box);
  });

  Future<void> signInAndLoad() async {
    expect(await auth.signIn(env.server.email, env.server.password), isNull);
    await env.container.read(scheduleRepositoryProvider).fetchWeek(monday);
    await env.container.read(gradesRepositoryProvider).fetch('');
  }

  test('connexion : identifiants et jeton enregistrés, état connecté', () async {
    await signInAndLoad();

    expect(env.container.read(authControllerProvider), isA<AuthSignedIn>());
    expect((await env.vault.readCredentials())?.email, env.server.email);
    expect(await env.vault.readApiToken(), isNotNull);
    expect(await env.vault.readEdcSession(), isNotNull);
    expect(box.isNotEmpty, isTrue);
  });

  test('mauvais mot de passe : erreur claire, une seule tentative', () async {
    final Failure? failure = await auth.signIn(env.server.email, 'faux');

    expect(failure, isA<InvalidCredentialsFailure>());
    expect(failure?.message, 'Identifiant ou mot de passe incorrect');
    expect(env.server.loginCalls, 1);
    expect(env.container.read(authControllerProvider), isA<AuthSignedOut>());
    expect(await env.vault.readCredentials(), isNull);
  });

  test('déconnexion : identifiants, jetons, session, cookies et cache effacés', () async {
    await signInAndLoad();

    await auth.signOut();

    expect(env.container.read(authControllerProvider), isA<AuthSignedOut>());
    expect(await env.vault.readCredentials(), isNull);
    expect(await env.vault.readApiToken(), isNull);
    expect(await env.vault.readEdcSession(), isNull);
    expect(env.store.values, isEmpty, reason: 'coffre entièrement vide');
    expect(box.isEmpty, isTrue, reason: 'cache vidé');
  });

  test('reconnexion après déconnexion : repart de zéro (nouvelle poignée de main)', () async {
    await signInAndLoad();
    await auth.signOut();
    final int entriesBefore = env.server.edcEntryCalls;

    await signInAndLoad();

    expect(env.server.edcEntryCalls, entriesBefore + 1);
  });

  test('identifiants refusés en arrière-plan : retour à la connexion avec message', () async {
    await signInAndLoad();
    env.server
      ..password = 'change-sur-le-portail'
      ..expireApiTokens()
      ..expireSchoolSession();

    await expectLater(
      env.container.read(scheduleRepositoryProvider).fetchWeek(monday),
      throwsA(isA<InvalidCredentialsFailure>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final AuthState state = env.container.read(authControllerProvider);
    expect(state, isA<AuthSignedOut>());
    expect((state as AuthSignedOut).message, 'Identifiant ou mot de passe incorrect');
    expect(box.isEmpty, isTrue);
  });
}
