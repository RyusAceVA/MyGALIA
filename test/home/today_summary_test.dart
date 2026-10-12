import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/features/home/domain/today_summary.dart';
import 'package:mygalia/features/schedule/domain/course.dart';

Course _c(DateTime day, int h1, int m1, int h2, int m2, String subject) => Course(
      start: DateTime(day.year, day.month, day.day, h1, m1),
      end: DateTime(day.year, day.month, day.day, h2, m2),
      subject: subject,
    );

void main() {
  final DateTime monday = DateTime(2026, 10, 12);
  final DateTime tuesday = DateTime(2026, 10, 13);
  final WeekSchedule week = WeekSchedule(monday: monday, courses: [
    _c(monday, 8, 30, 12, 0, 'DEVELOPPEMENT WEB'),
    _c(monday, 13, 30, 16, 30, 'RESEAUX'),
    _c(tuesday, 9, 0, 12, 0, 'ANGLAIS'),
  ]);

  test('pendant un cours : en cours, prochain et compteur', () {
    final TodaySummary s = TodaySummary.of(week, DateTime(2026, 10, 12, 10));

    expect(s.ongoing?.subject, 'DEVELOPPEMENT WEB');
    expect(s.next?.subject, 'RESEAUX');
    expect(s.remaining, 2);
    expect(s.today, hasLength(2));
  });

  test('entre deux cours : pas de cours en cours, le suivant', () {
    final TodaySummary s = TodaySummary.of(week, DateTime(2026, 10, 12, 12, 30));

    expect(s.ongoing, isNull);
    expect(s.next?.subject, 'RESEAUX');
    expect(s.remaining, 1);
  });

  test('journée terminée : le premier cours des jours suivants', () {
    final TodaySummary s = TodaySummary.of(week, DateTime(2026, 10, 12, 17));

    expect(s.ongoing, isNull);
    expect(s.next, isNull);
    expect(s.remaining, 0);
    expect(s.later?.subject, 'ANGLAIS');
  });

  test('journée en entreprise', () {
    final WeekSchedule company = WeekSchedule(monday: monday, courses: [
      _c(monday, 8, 30, 12, 0, 'Presence en entreprise'),
      _c(monday, 13, 0, 16, 30, 'Presence en entreprise'),
    ]);

    final TodaySummary s = TodaySummary.of(company, DateTime(2026, 10, 12, 10));

    expect(s.companyToday, isTrue);
    expect(s.ongoing, isNull);
    expect(s.remaining, 0);
  });

  test('week-end : rien aujourd\'hui, le lundi suivant', () {
    final DateTime nextMonday = DateTime(2026, 10, 19);
    final WeekSchedule next = WeekSchedule(monday: nextMonday, courses: [
      _c(nextMonday, 8, 30, 12, 0, 'CYBERSECURITE'),
    ]);

    final TodaySummary s = TodaySummary.of(next, DateTime(2026, 10, 17, 11));

    expect(s.weekend, isTrue);
    expect(s.today, isEmpty);
    expect(s.later?.subject, 'CYBERSECURITE');
  });
}
