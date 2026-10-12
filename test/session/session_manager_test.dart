import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/network/scform_config.dart';
import 'package:mygalia/core/session/school_client.dart';
import 'package:mygalia/features/auth/domain/edc_session.dart';
import 'package:mygalia/features/schedule/data/schedule_parser.dart';

import '../support/fake_scform_server.dart';
import '../support/test_env.dart';

/// Opération minimale : la page de planning d'un jour (corps brut).
Future<String> _planningPage(SchoolRequester school) => school.getPage(
      school.config.schoolUri(ScFormConfig.planningJournalierPath, {
        'id': school.planningId,
        'Jour': '13',
        'Mois': '10',
        'Annee': '2026',
      }),
      marker: ScheduleParser.pageMarker(DateTime(2026, 10, 13)),
    );

void main() {
  late TestEnv env;

  setUp(() async {
    env = await TestEnv.start();
    await env.storeCredentials();
  });

  tearDown(() => env.dispose());

  test('première requête : connexion API, jeton, chaîne de 302, données', () async {
    final String page = await env.school.run('test', _planningPage);

    expect(page, contains('Bouton_Info'));
    expect(env.server.loginCalls, 1);
    expect(env.server.getTokenCalls, 1);
    expect(env.server.edcEntryCalls, 1);
    final EdcSession session = await env.sessions.current();
    expect(session.jar.contains('.ASPXAUTH'), isTrue);
    expect(session.segment, startsWith('(S('));
    expect(session.planningId, '1543');
  });

  for (final ExpiryMode mode in [
    ExpiryMode.loginPage200,
    ExpiryMode.redirect302,
    ExpiryMode.unauthorized401,
    ExpiryMode.errorPage200,
  ]) {
    test('session expirée (${mode.name}) : reconnexion silencieuse et rejeu unique', () async {
      await env.school.run('test', _planningPage);
      env.server
        ..expiryMode = mode
        ..expireSchoolSession();
      final int planningBefore = env.server.planningCalls;

      final String page = await env.school.run('test', _planningPage);

      expect(page, contains('Bouton_Info'));
      expect(env.sessions.renewalCount, 2, reason: 'une seule reconnexion en plus');
      expect(env.server.edcEntryCalls, 2);
      expect(env.server.loginCalls, 1, reason: 'le jeton API était encore valable');
      expect(env.server.planningCalls - planningBefore, 2, reason: 'essai + rejeu');
    });
  }

  test('deux requêtes parallèles sur une session expirée : une seule reconnexion', () async {
    await env.school.run('test', _planningPage);
    env.server
      ..expireSchoolSession()
      ..getTokenDelay = const Duration(milliseconds: 200);

    final List<String> pages = await Future.wait([
      env.school.run('a', _planningPage),
      env.school.run('b', _planningPage),
      env.school.run('c', _planningPage),
    ]);

    expect(pages, everyElement(contains('Bouton_Info')));
    expect(env.sessions.renewalCount, 2);
    expect(env.server.getTokenCalls, 2);
    expect(env.server.edcEntryCalls, 2);
  });

  test('reconnexion refusée : identifiants purgés, pas de relance, événement', () async {
    await env.school.run('test', _planningPage);
    final Future<Failure> lost = env.sessions.sessionLost.first;
    env.server
      ..password = 'mot-de-passe-change'
      ..expireApiTokens()
      ..expireSchoolSession();
    final int loginsBefore = env.server.loginCalls;

    await expectLater(
      env.school.run('test', _planningPage),
      throwsA(isA<InvalidCredentialsFailure>()),
    );

    expect(env.server.loginCalls - loginsBefore, 1, reason: 'jamais relancé');
    expect(await env.vault.readCredentials(), isNull);
    expect(await lost, isA<InvalidCredentialsFailure>());
  });

  test('jeton API expiré côté serveur : nouvelle connexion API puis succès', () async {
    await env.school.run('test', _planningPage);
    env.server
      ..expireApiTokens()
      ..expireSchoolSession();

    final String page = await env.school.run('test', _planningPage);

    expect(page, contains('Bouton_Info'));
    expect(env.server.loginCalls, 2);
  });

  test('session persistée : un nouveau démarrage la réutilise sans poignée de main', () async {
    await env.school.run('test', _planningPage);
    final TestEnv restarted = await TestEnv.start(server: env.server, store: env.store);

    final String page = await restarted.school.run('test', _planningPage);

    expect(page, contains('Bouton_Info'));
    expect(env.server.edcEntryCalls, 1);
    expect(env.server.loginCalls, 1);
    await restarted.dispose(keepServer: true);
  });

  test('page vide persistante : rejeu unique puis erreur « données illisibles »', () async {
    await env.school.run('test', _planningPage);
    env.server.planningBodyOverride = '';

    await expectLater(
      env.school.run('test', _planningPage),
      throwsA(isA<DataFailure>()),
    );
    expect(env.sessions.renewalCount, 2, reason: 'une seule reconnexion');
  });

  test('erreurs 503 : deux relances au plus', () async {
    await env.school.run('test', _planningPage);
    env.server.planningServerErrors = 2;
    final int before = env.server.planningCalls;

    await env.school.run('test', _planningPage);
    expect(env.server.planningCalls - before, 3);

    env.server.planningServerErrors = 3;
    final int before2 = env.server.planningCalls;
    await expectLater(
      env.school.run('test', _planningPage),
      throwsA(isA<ServerFailure>()),
    );
    expect(env.server.planningCalls - before2, 3, reason: 'essai + 2 relances');
  });

  test('sans identifiants : SignedOutFailure, aucune requête de connexion', () async {
    await env.vault.clearAll();

    await expectLater(
      env.school.run('test', _planningPage),
      throwsA(isA<SignedOutFailure>()),
    );
    expect(env.server.loginCalls, 0);
  });

  test('après reset (déconnexion), une reconnexion en cours ne réécrit rien', () async {
    env.server.getTokenDelay = const Duration(milliseconds: 200);
    final Future<String> pending = env.school.run('test', _planningPage);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    env.sessions.reset();
    await env.vault.clearAll();

    await expectLater(pending, throwsA(isA<Failure>()));
    expect(await env.vault.readEdcSession(), isNull);
  });
}
