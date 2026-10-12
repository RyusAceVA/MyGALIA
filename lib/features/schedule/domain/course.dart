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

  static final RegExp _companyPresence = RegExp(
    r'pr[éeÉE]sence\s+en\s+entreprise',
    caseSensitive: false,
  );

  /// Jour de la séance (minuit, heure locale).
  DateTime get day => DateTime(start.year, start.month, start.day);

  /// Présence en entreprise (alternance) : pas un cours à l'école.
  bool get isCompanyPresence => <String?>[subject, group, teachers, room]
      .whereType<String>()
      .any(_companyPresence.hasMatch);

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

/// Premier vrai cours (hors présence en entreprise) qui commence après
/// [instant] dans la semaine, ou `null`.
Course? firstSchoolCourseAfter(WeekSchedule week, DateTime instant) => week.courses
    .where((Course c) => !c.isCompanyPresence && c.start.isAfter(instant))
    .firstOrNull;

/// Nature d'un jour ouvré, du point de vue de l'alternance.
enum DayKind {
  /// Au moins un vrai cours à l'école.
  school,

  /// Uniquement de la présence en entreprise.
  company,

  /// Rien de prévu (vacances, jour libre).
  empty,
}

DayKind dayKindOf(Iterable<Course> courses) {
  bool company = false;
  for (final Course course in courses) {
    if (!course.isCompanyPresence) return DayKind.school;
    company = true;
  }
  return company ? DayKind.company : DayKind.empty;
}

/// Lundi de la semaine de [date]. Calcul calendaire (et non par soustraction
/// de durées) : insensible aux changements d'heure.
DateTime mondayOf(DateTime date) =>
    DateTime(date.year, date.month, date.day - (date.weekday - 1));

/// [date] à minuit.
DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// [date] si c'est un jour ouvré, sinon le lundi suivant.
DateTime weekdayOnOrAfter(DateTime date) {
  DateTime day = dateOnly(date);
  while (day.weekday > DateTime.friday) {
    day = DateTime(day.year, day.month, day.day + 1);
  }
  return day;
}

/// Jour ouvré suivant (le vendredi mène au lundi).
DateTime nextWeekday(DateTime date) =>
    weekdayOnOrAfter(DateTime(date.year, date.month, date.day + 1));

/// Jour ouvré précédent (le lundi mène au vendredi).
DateTime previousWeekday(DateTime date) {
  DateTime day = DateTime(date.year, date.month, date.day - 1);
  while (day.weekday > DateTime.friday) {
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return day;
}
