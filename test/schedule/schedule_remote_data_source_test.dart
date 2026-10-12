import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/features/schedule/data/schedule_remote_data_source.dart';
import 'package:mygalia/features/schedule/domain/course.dart';

import '../support/test_env.dart';

void main() {
  late TestEnv env;
  final DateTime monday = DateTime(2026, 10, 12);

  setUp(() async {
    env = await TestEnv.start();
    await env.storeCredentials();
  });

  tearDown(() => env.dispose());

  test('semaine complète : 5 requêtes séquentielles, une séance par jour', () async {
    final WeekSchedule week = await env.container
        .read(scheduleRemoteDataSourceProvider)
        .fetchWeek(monday);

    expect(env.server.planningCalls, 5);
    expect(week.courses, hasLength(5));
    for (int i = 0; i < 5; i++) {
      final DateTime day = DateTime(2026, 10, 12 + i);
      expect(week.coursesOn(day).single.subject, 'DEVELOPPEMENT WEB');
    }
  });

  test("la première erreur interrompt la semaine (pas de semaine partielle)", () async {
    env.server.planningBodyOverride = 'contenu corrompu sans balise';

    await expectLater(
      env.container.read(scheduleRemoteDataSourceProvider).fetchWeek(monday),
      throwsA(isA<DataFailure>()),
    );
    expect(
      env.server.planningCalls,
      2,
      reason: 'lundi : essai + rejeu après reconnexion ; jours suivants non demandés',
    );
  });
}
