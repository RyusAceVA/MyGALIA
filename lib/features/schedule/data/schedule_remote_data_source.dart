import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/network/scform_config.dart';
import 'package:mygalia/core/session/school_client.dart';
import 'package:mygalia/features/schedule/data/schedule_parser.dart';
import 'package:mygalia/features/schedule/domain/course.dart';

/// Récupération du planning (§3) : le serveur ne renvoie qu'UNE journée par
/// requête.
class ScheduleRemoteDataSource {
  ScheduleRemoteDataSource(this._school);

  final SchoolClient _school;

  /// Semaine du lundi [monday] au vendredi.
  ///
  /// Les jours sont demandés l'un après l'autre, jamais en rafale parallèle,
  /// par respect du serveur. La première erreur interrompt la semaine : une
  /// semaine incomplète n'est jamais renvoyée (ni mise en cache).
  Future<WeekSchedule> fetchWeek(
    DateTime monday, {
    CancelToken? cancelToken,
  }) async {
    final Set<Course> courses = <Course>{};
    for (int i = 0; i < 5; i++) {
      final DateTime day = DateTime(monday.year, monday.month, monday.day + i);
      courses.addAll(
        await _school.run(
          'planning du ${day.day}/${day.month}',
          (SchoolRequester school) => _fetchDay(school, day),
          cancelToken: cancelToken,
        ),
      );
    }
    final List<Course> sorted = courses.toList()
      ..sort((Course a, Course b) => a.start.compareTo(b.start));
    return WeekSchedule(monday: monday, courses: sorted);
  }

  static Future<List<Course>> _fetchDay(
    SchoolRequester school,
    DateTime day,
  ) async {
    final Uri uri = school.config.schoolUri(
      ScFormConfig.planningJournalierPath,
      {
        'id': school.planningId,
        'Jour': '${day.day}',
        'Mois': '${day.month}',
        'Annee': '${day.year}',
      },
    );
    return ScheduleParser.parseDay(await school.getPage(uri));
  }
}

final scheduleRemoteDataSourceProvider = Provider<ScheduleRemoteDataSource>((ref) {
  return ScheduleRemoteDataSource(ref.watch(schoolClientProvider));
});
