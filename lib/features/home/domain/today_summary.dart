import 'package:flutter/foundation.dart';

import 'package:mygalia/features/schedule/domain/course.dart';

/// Ce que l'accueil doit dire de la journée, à un instant donné.
@immutable
class TodaySummary {
  const TodaySummary._({
    required this.today,
    required this.ongoing,
    required this.next,
    required this.later,
    required this.remaining,
    required this.companyToday,
    required this.weekend,
  });

  /// [week] : semaine du jour (ou la suivante le week-end).
  factory TodaySummary.of(WeekSchedule week, DateTime now) {
    final DateTime today = dateOnly(now);
    final List<Course> todays = week.coursesOn(today);
    final List<Course> school =
        todays.where((Course c) => !c.isCompanyPresence).toList();
    final DateTime tomorrow = DateTime(today.year, today.month, today.day + 1);
    return TodaySummary._(
      today: todays,
      ongoing: school
          .where((Course c) => !c.start.isAfter(now) && c.end.isAfter(now))
          .firstOrNull,
      next: school.where((Course c) => c.start.isAfter(now)).firstOrNull,
      later: week.courses
          .where((Course c) => !c.isCompanyPresence && !c.start.isBefore(tomorrow))
          .firstOrNull,
      remaining: school.where((Course c) => c.end.isAfter(now)).length,
      companyToday: todays.isNotEmpty && school.isEmpty,
      weekend: now.weekday > DateTime.friday,
    );
  }

  /// Toutes les séances du jour (présence en entreprise comprise).
  final List<Course> today;

  /// Cours en cours, s'il y en a un.
  final Course? ongoing;

  /// Prochain cours du jour.
  final Course? next;

  /// Premier cours d'un jour suivant de la même semaine.
  final Course? later;

  /// Cours pas encore terminés aujourd'hui (celui en cours compris).
  final int remaining;

  /// Journée uniquement en entreprise.
  final bool companyToday;

  final bool weekend;
}
