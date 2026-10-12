import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/network/scform_config.dart';
import 'package:mygalia/features/grades/domain/grade.dart';

/// Contenu utile d'une page `MesNotes.aspx`.
class GradesPage {
  const GradesPage({
    required this.grades,
    required this.periods,
    required this.selectedPeriod,
    required this.periodFieldName,
    required this.formFields,
  });

  final List<Grade> grades;
  final List<SchoolPeriod> periods;
  final String? selectedPeriod;

  /// Nom WebForms réel du sélecteur de semestre (pour `__EVENTTARGET`).
  final String? periodFieldName;

  /// Tous les champs que le navigateur posterait (§4.1 c).
  final Map<String, String> formFields;

  GradesSnapshot toSnapshot() => GradesSnapshot(
        periods: periods,
        selectedPeriod: selectedPeriod,
        grades: grades,
      );
}

/// Parsing de la page des notes, formulaire ASP.NET WebForms (§4).
abstract final class GradesParser {
  GradesParser._();

  /// Regex d'origine (§4.1 a), ancrée sur des repères sémantiques stables :
  /// note, « /20 », coefficient, matière, date « du JJ/MM/AAAA », type.
  static final RegExp _gradeBlock = RegExp(
    r'>([\d.,]+)</span>\s*<span[^>]*>\s*/20\s*</span>'
    r'.*?coeff\.\s*([\d,]+)'
    r'.*?<td[^>]*>\s*<span[^>]*>([^<]+)</span>'
    r'.*?du\s+(\d{2}/\d{2}/\d{4})'
    r'[^<]*</span>\s*<span[^>]*>([^<]*)</span>',
    dotAll: true,
  );

  static final RegExp _date = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$');
  static final RegExp _spaces = RegExp(r'\s+');

  /// Repère d'une vraie page de notes : le sélecteur de semestre, ou au
  /// moins une note « /20 ». Sans lui, la page n'est pas une page de notes
  /// (même si elle contient un champ mot de passe ailleurs).
  static final RegExp pageMarker = RegExp(r'DropDownLstPeriode|>\s*/20\s*<');

  /// Lève [DataFailure] si la page n'est pas une page de notes : ni
  /// sélecteur de semestre, ni note reconnaissable. Un semestre sans note
  /// (sélecteur présent) reste une page valide.
  static GradesPage parse(String html) {
    final Document document = html_parser.parse(html);
    final Element? select = _periodSelect(document);
    final List<Grade> grades = parseGrades(html);
    if (select == null && grades.isEmpty) {
      throw const DataFailure('La page des notes reçue est illisible.');
    }
    return GradesPage(
      grades: grades,
      periods: select == null ? const <SchoolPeriod>[] : _periods(select),
      selectedPeriod: select == null ? null : _selectedValue(select),
      periodFieldName: select?.attributes['name'],
      formFields: extractFormFields(document),
    );
  }

  static List<Grade> parseGrades(String html) => [
        for (final RegExpMatch m in _gradeBlock.allMatches(html))
          if (_number(m.group(1)!) case final double value)
            Grade(
              value: value,
              coefficient: _number(m.group(2)!) ?? 1,
              subject: _text(m.group(3)!),
              date: _parseDate(m.group(4)!),
              type: _text(m.group(5)!).isEmpty ? null : _text(m.group(5)!),
            ),
      ];

  /// Tout ce qu'un navigateur posterait : champs `input` (cachés, texte…),
  /// radios et cases COCHÉS uniquement, valeur sélectionnée de chaque
  /// `select`, `textarea`. Les boutons ne sont pas inclus : le postback est
  /// déclenché par le `select`, pas par un clic.
  static Map<String, String> extractFormFields(Document document) {
    final Map<String, String> fields = <String, String>{};
    for (final Element input in document.querySelectorAll('input')) {
      final String? name = input.attributes['name'];
      if (name == null || name.isEmpty || input.attributes.containsKey('disabled')) {
        continue;
      }
      final String type = (input.attributes['type'] ?? 'text').toLowerCase();
      final String value = input.attributes['value'] ?? '';
      switch (type) {
        case 'radio' || 'checkbox':
          if (input.attributes.containsKey('checked')) {
            fields[name] = input.attributes['value'] ?? 'on';
          }
        case 'submit' || 'button' || 'image' || 'reset' || 'file':
          break;
        default:
          fields[name] = value;
      }
    }
    for (final Element select in document.querySelectorAll('select')) {
      final String? name = select.attributes['name'];
      if (name == null || name.isEmpty || select.attributes.containsKey('disabled')) {
        continue;
      }
      final String? value = _selectedValue(select);
      if (value != null) fields[name] = value;
    }
    for (final Element area in document.querySelectorAll('textarea')) {
      final String? name = area.attributes['name'];
      if (name != null && name.isNotEmpty) fields[name] = area.text;
    }
    return fields;
  }

  static Element? _periodSelect(Document document) {
    final List<Element> selects = document.querySelectorAll('select');
    return selects
            .where((Element s) => s.attributes['name'] == ScFormConfig.periodSelectName)
            .firstOrNull ??
        selects
            .where((Element s) =>
                (s.attributes['name'] ?? '').endsWith('DropDownLstPeriode'))
            .firstOrNull;
  }

  static List<SchoolPeriod> _periods(Element select) => [
        for (final Element option in select.querySelectorAll('option'))
          if ((option.attributes['value'] ?? '').isNotEmpty)
            SchoolPeriod(
              value: option.attributes['value']!,
              label: _clean(option.text),
            ),
      ];

  /// Option `selected`, sinon la première (comportement d'un navigateur).
  static String? _selectedValue(Element select) {
    final List<Element> options = select.querySelectorAll('option');
    if (options.isEmpty) return null;
    final Element chosen = options
            .where((Element o) => o.attributes.containsKey('selected'))
            .firstOrNull ??
        options.first;
    return chosen.attributes['value'] ?? _clean(chosen.text);
  }

  /// Nombre français (« 12,5 ») ou anglais (« 12.5 »).
  static double? _number(String raw) => double.tryParse(raw.replaceAll(',', '.'));

  static DateTime? _parseDate(String raw) {
    final Match? m = _date.firstMatch(raw);
    if (m == null) return null;
    return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
  }

  /// Texte capturé par la regex : entités décodées, espaces normalisés.
  static String _text(String raw) => _clean(html_parser.parseFragment(raw).text ?? raw);

  static String _clean(String text) => text.replaceAll(_spaces, ' ').trim();
}
