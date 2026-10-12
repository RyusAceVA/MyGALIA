import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/storage/cache_store.dart';
import 'package:mygalia/features/grades/data/grades_repository.dart';
import 'package:mygalia/features/grades/domain/grade.dart';
import 'package:mygalia/features/schedule/data/schedule_repository.dart';
import 'package:mygalia/features/schedule/domain/course.dart';

import '../support/fake_scform_server.dart';
import '../support/hive_test_utils.dart';
import '../support/test_env.dart';

void main() {
  late TestEnv env;
  late Box<dynamic> box;
  late ScheduleRepository schedule;
  final DateTime monday = DateTime(2026, 10, 12);

  setUp(() async {
    box = await openTestBox();
    env = await TestEnv.start(
      overrides: [cacheStoreProvider.overrideWithValue(CacheStore(box))],
    );
    await env.storeCredentials();
    schedule = env.container.read(scheduleRepositoryProvider);
  });

  tearDown(() async {
    await env.dispose();
    await deleteTestBox(box);
  });

  test('semaine valide : mise en cache après parsing réussi', () async {
    final CachedValue<WeekSchedule> fetched = await schedule.fetchWeek(monday);

    final CachedValue<WeekSchedule>? cached = schedule.cachedWeek(monday);
    expect(cached, isNotNull);
    expect(cached!.data.courses, fetched.data.courses);
    expect(cached.savedAt, fetched.savedAt);
  });

  test('réponse vide : erreur typée, rien en cache', () async {
    env.server.planningBodyOverride = '';

    await expectLater(schedule.fetchWeek(monday), throwsA(isA<DataFailure>()));
    expect(schedule.cachedWeek(monday), isNull);
    expect(box.isEmpty, isTrue);
  });

  test('réponse corrompue : erreur typée, rien en cache', () async {
    env.server.planningBodyOverride = '\u0000\u0001 garbage {"not":"html"}';

    await expectLater(schedule.fetchWeek(monday), throwsA(isA<DataFailure>()));
    expect(box.isEmpty, isTrue);
  });

  test('page de connexion persistante : rien en cache', () async {
    env.server
      ..expiryMode = ExpiryMode.loginPage200
      ..planningBodyOverride = FakeScFormServer.loginPageHtml;

    await expectLater(schedule.fetchWeek(monday), throwsA(isA<SessionFailure>()));
    expect(box.isEmpty, isTrue);
  });

  test('un rafraîchissement raté laisse intact le dernier cache valide', () async {
    final CachedValue<WeekSchedule> valid = await schedule.fetchWeek(monday);
    env.server.planningBodyOverride = 'corrompu';

    await expectLater(schedule.fetchWeek(monday), throwsA(isA<DataFailure>()));

    final CachedValue<WeekSchedule>? cached = schedule.cachedWeek(monday);
    expect(cached?.savedAt, valid.savedAt);
    expect(cached?.data.courses, valid.data.courses);
  });

  test('notes : une entrée de cache par semestre', () async {
    final GradesRepository grades = env.container.read(gradesRepositoryProvider);

    await grades.fetch('');
    await grades.fetch('31');

    expect(grades.cached('')?.data.selectedPeriod, '30');
    expect(
      grades.cached('31')?.data.grades.map((Grade g) => g.subject),
      ['Anglais technique'],
    );
  });
}
