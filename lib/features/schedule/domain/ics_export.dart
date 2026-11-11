import 'dart:convert';

import 'package:mygalia/features/schedule/domain/course.dart';

/// Export d'un planning au format iCalendar (RFC 5545), lisible par tous les
/// agendas (Google Agenda, Samsung, Outlook…).
///
///  * Seuls les vrais cours sont exportés : la présence en entreprise
///    remplirait l'agenda de journées entières sans intérêt.
///  * Chaque séance a un identifiant stable (date, heure, matière) : importer
///    deux fois la même semaine met à jour les événements au lieu de les
///    dupliquer, dans les agendas qui respectent l'identifiant.
///  * Les heures sont écrites en UTC : l'agenda les réaffiche à l'heure
///    locale, quel que soit le fuseau du téléphone.
abstract final class IcsExport {
  IcsExport._();

  /// Vrais cours de [courses] (présence en entreprise exclue), triés.
  static List<Course> exportable(Iterable<Course> courses) =>
      courses.where((Course c) => !c.isCompanyPresence).toList()
        ..sort((Course a, Course b) => a.start.compareTo(b.start));

  /// Contenu du fichier `.ics`. [now] : horodatage de l'export.
  static String calendar(Iterable<Course> courses, {required DateTime now}) {
    final List<String> lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//MyGalia//Planning//FR',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      for (final Course course in exportable(courses)) ..._event(course, now),
      'END:VCALENDAR',
    ];
    // Lignes pliées à 75 octets, fins de ligne CRLF (RFC 5545 §3.1).
    return '${lines.expand(_fold).join('\r\n')}\r\n';
  }

  /// Nom de fichier d'une semaine : `planning-2026-10-12.ics`.
  static String fileName(DateTime monday) =>
      'planning-${monday.year}-${_two(monday.month)}-${_two(monday.day)}.ics';

  static List<String> _event(Course course, DateTime now) {
    final String? room = course.room;
    final String description = <String?>[course.teachers, course.group]
        .whereType<String>()
        .where((String s) => s.isNotEmpty)
        .join('\n');
    return <String>[
      'BEGIN:VEVENT',
      'UID:${_uid(course)}',
      'DTSTAMP:${_utc(now)}',
      'DTSTART:${_utc(course.start)}',
      'DTEND:${_utc(course.end)}',
      'SUMMARY:${_escape(course.subject)}',
      if (room != null && room.isNotEmpty) 'LOCATION:${_escape(room)}',
      if (description.isNotEmpty) 'DESCRIPTION:${_escape(description)}',
      'END:VEVENT',
    ];
  }

  /// Identifiant stable : même séance, même identifiant d'un export à l'autre.
  static String _uid(Course course) {
    final DateTime s = course.start;
    final String slug = base64Url
        .encode(utf8.encode(course.subject))
        .replaceAll('=', '');
    return '${s.year}${_two(s.month)}${_two(s.day)}T${_two(s.hour)}${_two(s.minute)}'
        '-$slug@mygalia';
  }

  static String _utc(DateTime local) {
    final DateTime t = local.toUtc();
    return '${t.year.toString().padLeft(4, '0')}${_two(t.month)}${_two(t.day)}'
        'T${_two(t.hour)}${_two(t.minute)}${_two(t.second)}Z';
  }

  /// Échappement des textes (RFC 5545 §3.3.11).
  static String _escape(String text) => text
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll(RegExp(r'\r\n|\r|\n'), r'\n');

  /// Plie une ligne à 75 octets UTF-8 sans couper un caractère.
  static Iterable<String> _fold(String line) sync* {
    final StringBuffer current = StringBuffer();
    int bytes = 0;
    int limit = 75;
    for (final int rune in line.runes) {
      final String char = String.fromCharCode(rune);
      final int size = utf8.encode(char).length;
      if (bytes + size > limit) {
        yield current.toString();
        current
          ..clear()
          ..write(' ');
        bytes = 1;
        limit = 75;
      }
      current.write(char);
      bytes += size;
    }
    yield current.toString();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
