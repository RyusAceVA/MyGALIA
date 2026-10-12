import 'package:flutter/foundation.dart';

/// Une séance de l'emploi du temps (§3.3 de la rétro-ingénierie).
@immutable
class Course {
  const Course({
    required this.start,
    required this.end,
    required this.subject,
    this.group,
    this.teachers,
    this.room,
  });

  final DateTime start;
  final DateTime end;
  final String subject;
  final String? group;
  final String? teachers;
  final String? room;

  /// Jour de la séance (minuit, heure locale).
  DateTime get day => DateTime(start.year, start.month, start.day);

  Map<String, Object?> toJson() => {
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'subject': subject,
        'group': group,
        'teachers': teachers,
        'room': room,
      };

  /// Lève une erreur si le contenu est incomplet (cache corrompu).
  static Course fromJson(Map<String, Object?> json) => Course(
        start: DateTime.parse(json['start']! as String),
        end: DateTime.parse(json['end']! as String),
        subject: json['subject']! as String,
        group: json['group'] as String?,
        teachers: json['teachers'] as String?,
        room: json['room'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is Course &&
      other.start == start &&
      other.end == end &&
      other.subject == subject &&
      other.group == group &&
      other.teachers == teachers &&
      other.room == room;

  @override
  int get hashCode => Object.hash(start, end, subject, group, teachers, room);
}

/// Semaine de cours, du lundi [monday] au vendredi.
@immutable
class WeekSchedule {
  const WeekSchedule({required this.monday, required this.courses});

  final DateTime monday;
  final List<Course> courses;

  /// Séances du jour [day], triées par heure.
  List<Course> coursesOn(DateTime day) {
    final DateTime target = DateTime(day.year, day.month, day.day);
    return courses.where((Course c) => c.day == target).toList();
  }

  Map<String, Object?> toJson() => {
        'monday': monday.toIso8601String(),
        'courses': [for (final Course c in courses) c.toJson()],
      };

  static WeekSchedule fromJson(Map<String, Object?> json) => WeekSchedule(
        monday: DateTime.parse(json['monday']! as String),
        courses: [
          for (final Object? c in json['courses']! as List<Object?>)
            Course.fromJson((c! as Map<Object?, Object?>).cast<String, Object?>()),
        ],
      );
}

/// Lundi de la semaine de [date]. Calcul calendaire (et non par soustraction
/// de durées) : insensible aux changements d'heure.
DateTime mondayOf(DateTime date) =>
    DateTime(date.year, date.month, date.day - (date.weekday - 1));
