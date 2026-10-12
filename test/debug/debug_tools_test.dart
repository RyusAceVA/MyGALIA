import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/storage/cache_store.dart';
import 'package:mygalia/features/auth/presentation/auth_controller.dart';
import 'package:mygalia/features/grades/data/grades_repository.dart';
import 'package:mygalia/features/schedule/data/schedule_repository.dart';
import 'package:mygalia/features/schedule/domain/course.dart';

import '../support/fake_scform_server.dart';
import '../support/hive_test_utils.dart';
import '../support/test_env.dart';

void main() {
  late TestEnv env;
  late Box<dynamic> box;
  final DateTime monday = DateTime(2026, 10, 12);

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

  Future<WeekSchedule> fetchWeek() async =>
      (await env.container.read(scheduleRepositoryProvider).fetchWeek(monday)).data;

  test('« Invalider la session » : la requête suivante se répare seule', () async {
    await fetchWeek();
    final int renewals = env.sessions.renewalCount;
    final int logins = env.server.loginCalls;

    expect(await env.sessions.debugInvalidate(alsoApiToken: false), isTrue);
    final WeekSchedule week = await fetchWeek();

    expect(week.courses, hasLength(5));
    expect(env.sessions.renewalCount, renewals + 1);
    expect(env.server.loginCalls, logins, reason: 'le jeton API restait valable');
  });

  test('« Invalider aussi le jeton API » : nouvelle connexion API puis succès', () async {
    await fetchWeek();
    final int logins = env.server.loginCalls;

    await env.sessions.debugInvalidate(alsoApiToken: true);
    final WeekSchedule week = await fetchWeek();

    expect(week.courses, hasLength(5));
    expect(env.server.loginCalls, logins + 1);
  });

  test('résumé de session : noms de cookies, jamais leurs valeurs', () async {
    await fetchWeek();

    final String summary = env.sessions.debugSummary();

    expect(summary, contains('.ASPXAUTH'));
    for (final String secret in env.server.issuedSecrets) {
      expect(summary, isNot(contains(secret)));
    }
  });

  test('aucun mot de passe, cookie, jeton ni e-mail dans les journaux', () async {
    AppLog.clear();
    final List<String> printed = <String>[];
    final DebugPrintCallback original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => printed.add(message ?? '');
    try {
      await env.vault.clearAll();
      env.container.listen(authControllerProvider, (_, __) {});
      final AuthController auth = env.container.read(authControllerProvider.notifier);
      await auth.signIn(env.server.email, 'mauvais-mot-de-passe');
      await auth.signIn(env.server.email, env.server.password);
      await fetchWeek();
      await env.container.read(gradesRepositoryProvider).fetch('31');
      env.server
        ..expiryMode = ExpiryMode.redirect302
        ..expireSchoolSession();
      await fetchWeek();
      await env.sessions.debugInvalidate(alsoApiToken: true);
      await fetchWeek();
    } finally {
      debugPrint = original;
    }

    final String logs = [
      ...printed,
      ...AppLog.entries.map((LogEntry e) => e.message),
    ].join('\n');
    expect(logs, contains('→ POST'), reason: 'le journal a bien fonctionné');
    for (final String secret in [
      env.server.password,
      'mauvais-mot-de-passe',
      env.server.email,
      Uri.encodeQueryComponent(env.server.email),
      FakeScFormServer.viewState,
      ...env.server.issuedSecrets,
    ]) {
      expect(logs, isNot(contains(secret)), reason: 'secret présent dans les journaux');
    }
  });
}
