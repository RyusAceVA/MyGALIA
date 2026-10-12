import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/features/schedule/domain/course.dart';

/// Parsing d'une page « PlanningJournalier » (§3.3 de la rétro-ingénierie).
///
/// Chaque séance est un `<div class="Bouton_Info">` dont l'attribut `title`
/// (multi-lignes) contient : horaires, groupe, matière, formateur(s), salle.
abstract final class ScheduleParser {
  ScheduleParser._();

  /// Ligne 0 : date puis les deux horaires. Le `.*?` absorbe le « à »
  /// (souvent encodé) et la durée « (03h30) » (regex d'origine).
  static final RegExp _timeLine = RegExp(
    r'(\d{1,2})/(\d{1,2})/(\d{4}).*?(\d{1,2}):(\d{2}).*?(\d{1,2}):(\d{2})',
  );

  /// Début d'un `title` de séance (« Le 01/07/2026 … »).
  static final RegExp _courseTitle = RegExp(r'^\s*Le\s+\d{1,2}/\d{1,2}/\d{4}');

  /// Une page de planning est du HTML : sinon, contenu corrompu.
  static final RegExp _htmlMarker =
      RegExp(r'<\s*(html|body|div|table)\b', caseSensitive: false);

  /// Code de groupe/classe (ex. « TSRS1 ») : majuscules et au moins un chiffre.
  static final RegExp _groupCode = RegExp(r'^[A-Z0-9][A-Z0-9 _./-]{0,19}$');
  static final RegExp _digit = RegExp(r'\d');
  static final RegExp _lineBreak = RegExp(r'\r\n|\r|\n');
  static final RegExp _spaces = RegExp(r'\s+');

  /// Séances d'une page journalière, triées par heure.
  ///
  /// Lève [DataFailure] si la page n'est pas du HTML, ou si elle contient
  /// des séances toutes illisibles (format changé côté SC Form). Une page
  /// sans séance (jour sans cours) est valide.
  static List<Course> parseDay(String html) {
    if (!_htmlMarker.hasMatch(html)) {
      throw const DataFailure('La page de planning reçue est illisible.');
    }
    final Document document = html_parser.parse(html);
    List<Element> blocks = document.querySelectorAll('.Bouton_Info');
    if (blocks.isEmpty) {
      // Repli si la classe CSS change : tout élément dont le title ressemble
      // à celui d'une séance.
      blocks = document
          .querySelectorAll('[title]')
          .where((Element e) => _courseTitle.hasMatch(e.attributes['title'] ?? ''))
          .toList();
    }

    final Set<String> seenTitles = <String>{};
    final List<Course> courses = <Course>[];
    int unreadable = 0;
    for (final Element block in blocks) {
      final String title = (block.attributes['title'] ?? '').trim();
      // Créneau vide, ou séance rendue plusieurs fois (rowspan).
      if (title.isEmpty || !seenTitles.add(title)) continue;
      final List<String> lines = _lines(title);
      if (lines.isEmpty) continue;
      if (!_timeLine.hasMatch(lines.first)) {
        unreadable++;
        continue;
      }
      final Course? course = _fromLines(lines);
      if (course != null) courses.add(course);
    }

    if (courses.isEmpty && unreadable > 0) {
      throw const DataFailure(
        'Le format du planning a changé : séances illisibles.',
      );
    }
    courses.sort((Course a, Course b) => a.start.compareTo(b.start));
    return courses;
  }

  /// Séance décrite par un `title` (entités déjà décodées), ou `null` si
  /// c'est un créneau vide ou un format inconnu.
  static Course? parseTitle(String title) {
    final List<String> lines = _lines(title);
    return lines.isEmpty ? null : _fromLines(lines);
  }

  static List<String> _lines(String title) => title
      .split(_lineBreak)
      .map((String l) => l.replaceAll(_spaces, ' ').trim())
      .where((String l) => l.isNotEmpty)
      .toList();

  static Course? _fromLines(List<String> lines) {
    final Match? time = _timeLine.firstMatch(lines.first);
    if (time == null) return null;
    int at(int group) => int.parse(time.group(group)!);
    final DateTime start = DateTime(at(3), at(2), at(1), at(4), at(5));
    final DateTime end = DateTime(at(3), at(2), at(1), at(6), at(7));

    final List<String> rest = lines.sublist(1);
    String? group;
    String? subject;
    String? teachers;
    String? room;
    if (rest.length >= 4) {
      // Format complet : groupe, matière, formateur(s) (une ou plusieurs
      // lignes), salle.
      group = rest.first;
      subject = rest[1];
      teachers = rest.sublist(2, rest.length - 1).join(', ');
      room = rest.last;
    } else if (rest.isNotEmpty) {
      // Format réduit : certaines séances omettent le groupe ou la salle.
      int i = 0;
      if (rest.length >= 2 && _isGroupCode(rest.first)) group = rest[i++];
      subject = rest[i++];
      final List<String> others = rest.sublist(i);
      if (others.length >= 2) {
        teachers = others.first;
        room = others[1];
      } else if (others.length == 1) {
        teachers = others.first;
      }
    }
    if (subject == null || subject.isEmpty) return null;
    return Course(
      start: start,
      end: end,
      subject: subject,
      group: group,
      teachers: teachers,
      room: room,
    );
  }

  static bool _isGroupCode(String line) =>
      _groupCode.hasMatch(line) && _digit.hasMatch(line);
}
