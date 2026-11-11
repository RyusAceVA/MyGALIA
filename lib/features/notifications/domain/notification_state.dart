import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:mygalia/core/utils/date_format_fr.dart';
import 'package:mygalia/features/grades/domain/grade.dart';
import 'package:mygalia/features/schedule/domain/course.dart';

/// Réglages et mémoire des notifications.
///
/// Conservé dans le coffre (et non dans Hive) : la tâche de fond tourne dans
/// un autre isolat, et le coffre est le seul stockage que les deux peuvent
/// lire et écrire sans se marcher dessus.
@immutable
class NotificationState {
  const NotificationState({
    this.newGrades = false,
    this.fridayReminder = false,
    this.gradesBaseline = false,
    this.knownGrades = const <String>{},
    this.remindedWeek,
  });

  /// Prévenir quand une nouvelle note apparaît.
  final bool newGrades;

  /// Le vendredi, rappeler les cours de la semaine suivante.
  final bool fridayReminder;

  /// Faux tant qu'aucune liste de notes n'a été vue : la première sert de
  /// point de départ, sans notifier toutes les notes déjà là.
  final bool gradesBaseline;

  /// Empreintes des notes déjà vues (voir [gradeSignature]).
  final Set<String> knownGrades;

  /// Lundi (AAAA-MM-JJ) de la dernière semaine déjà traitée par le rappel.
  final String? remindedWeek;

  bool get anyEnabled => newGrades || fridayReminder;

  /// Les plus anciennes empreintes sont oubliées au-delà de cette taille.
  static const int maxKnownGrades = 400;

  NotificationState copyWith({
    bool? newGrades,
    bool? fridayReminder,
    bool? gradesBaseline,
    Set<String>? knownGrades,
    String? remindedWeek,
  }) =>
      NotificationState(
        newGrades: newGrades ?? this.newGrades,
        fridayReminder: fridayReminder ?? this.fridayReminder,
        gradesBaseline: gradesBaseline ?? this.gradesBaseline,
        knownGrades: knownGrades ?? this.knownGrades,
        remindedWeek: remindedWeek ?? this.remindedWeek,
      );

  Map<String, Object?> toJson() => {
        'newGrades': newGrades,
        'fridayReminder': fridayReminder,
        'gradesBaseline': gradesBaseline,
        'knownGrades': knownGrades.toList(),
        'remindedWeek': remindedWeek,
      };

  /// Contenu inattendu : réglages par défaut (notifications coupées).
  static NotificationState fromJson(Map<String, Object?> json) {
    final Object? known = json['knownGrades'];
    return NotificationState(
      newGrades: json['newGrades'] == true,
      fridayReminder: json['fridayReminder'] == true,
      gradesBaseline: json['gradesBaseline'] == true,
      knownGrades: known is List ? known.whereType<String>().toSet() : const <String>{},
      remindedWeek: json['remindedWeek'] as String?,
    );
  }
}

/// Empreinte d'une note : assez pour la reconnaître, sans la stocker.
String gradeSignature(Grade grade) {
  final String raw = [
    grade.subject,
    grade.date?.toIso8601String() ?? '',
    grade.value?.toString() ?? grade.mention ?? '',
    grade.outOf,
    grade.coefficient,
    grade.type ?? '',
  ].join('|');
  // FNV-1a 64 bits, en base 36 : court, stable d'un lancement à l'autre.
  int hash = 0xcbf29ce484222325;
  for (final int byte in utf8.encode(raw)) {
    hash = ((hash ^ byte) * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash.toRadixString(36);
}

/// Résultat de la comparaison d'une liste de notes avec la mémoire.
@immutable
class GradeCheck {
  const GradeCheck(this.state, this.fresh);

  /// Mémoire mise à jour (à enregistrer).
  final NotificationState state;

  /// Notes jamais vues, à annoncer (vide lors du point de départ).
  final List<Grade> fresh;
}

/// Compare [grades] à la mémoire. La toute première liste sert de point de
/// départ : elle est mémorisée sans rien annoncer.
GradeCheck checkGrades(NotificationState state, List<Grade> grades) {
  final List<Grade> fresh = <Grade>[];
  final List<String> known = state.knownGrades.toList();
  final Set<String> seen = state.knownGrades.toSet();
  for (final Grade grade in grades) {
    final String signature = gradeSignature(grade);
    if (seen.add(signature)) {
      known.add(signature);
      if (state.gradesBaseline) fresh.add(grade);
    }
  }
  final int extra = known.length - NotificationState.maxKnownGrades;
  return GradeCheck(
    state.copyWith(
      gradesBaseline: true,
      knownGrades: (extra > 0 ? known.sublist(extra) : known).toSet(),
    ),
    fresh,
  );
}

/// Texte d'une notification.
@immutable
class NotificationText {
  const NotificationText(this.title, this.body);

  final String title;
  final String body;
}

String _gradeLabel(Grade grade) {
  final double? value = grade.value;
  if (value == null) return grade.mention ?? '—';
  String number(double n) => n == n.roundToDouble()
      ? n.toStringAsFixed(0)
      : n.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceAll('.', ',');
  return '${number(value)}/${number(grade.outOf)}';
}

/// Annonce de [fresh] nouvelles notes (non vide).
NotificationText describeNewGrades(List<Grade> fresh) {
  if (fresh.length == 1) {
    final Grade grade = fresh.single;
    return NotificationText(
      'Nouvelle note',
      '${grade.subject} : ${_gradeLabel(grade)}',
    );
  }
  final String list = fresh
      .take(3)
      .map((Grade g) => '${g.subject} ${_gradeLabel(g)}')
      .join(' · ');
  return NotificationText(
    '${fresh.length} nouvelles notes',
    fresh.length > 3 ? '$list…' : list,
  );
}

/// Rappel du vendredi.
abstract final class FridayReminder {
  FridayReminder._();

  /// Heure à partir de laquelle le rappel peut partir le vendredi.
  static const int fromHour = 12;

  /// Lundi de la semaine à annoncer si c'est le moment (du vendredi midi au
  /// dimanche soir), sinon `null`.
  static DateTime? weekToAnnounce(DateTime now) {
    final bool friday = now.weekday == DateTime.friday && now.hour >= fromHour;
    if (!friday && now.weekday < DateTime.saturday) return null;
    final DateTime monday = mondayOf(now);
    return DateTime(monday.year, monday.month, monday.day + 7);
  }

  /// Clé d'une semaine dans la mémoire.
  static String weekKey(DateTime monday) =>
      '${monday.year}-${monday.month.toString().padLeft(2, '0')}-'
      '${monday.day.toString().padLeft(2, '0')}';

  /// Texte du rappel pour [week], ou `null` si elle n'a aucun cours à
  /// l'école (entreprise, vacances) : rien à rappeler.
  static NotificationText? describe(WeekSchedule week) {
    final List<Course> school =
        week.courses.where((Course c) => !c.isCompanyPresence).toList()
          ..sort((Course a, Course b) => a.start.compareTo(b.start));
    if (school.isEmpty) return null;
    final Course first = school.first;
    final int days = school.map((Course c) => c.day).toSet().length;
    final String? room = first.room;
    return NotificationText(
      'Cours à l\'école la semaine prochaine',
      '${days == 1 ? '1 jour de cours' : '$days jours de cours'}. '
          'Reprise ${DateFormatFr.dayInline(first.start)} à '
          '${DateFormatFr.time(first.start)} : ${first.subject}'
          '${room == null || room.isEmpty ? '' : ' (${room.trim()})'}.',
    );
  }
}
