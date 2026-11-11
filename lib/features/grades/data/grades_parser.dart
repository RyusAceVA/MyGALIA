import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/network/scform_config.dart';
import 'package:mygalia/features/grades/domain/grade.dart';

/// Un sélecteur WebForms de la page des notes et la façon de le « changer ».
class FormSelect {
  const FormSelect({required this.name, required this.autoPostBack});

  /// Nom WebForms réel (pour `__EVENTTARGET`).
  final String name;

  /// Vrai si le changer recharge la page tout seul (`onchange` appelant
  /// `__doPostBack`) ; sinon il faut le bouton de validation du formulaire.
  final bool autoPostBack;
}

/// Contenu utile d'une page `MesNotes.aspx`.
class GradesPage {
  const GradesPage({
    required this.grades,
    this.unreadable = 0,
    required this.periods,
    required this.selectedPeriod,
    required this.periodFieldName,
    required this.formFields,
    this.classes = const <SchoolClass>[],
    this.selectedClass,
    this.classSelect,
    this.periodSelect,
    this.submitButton,
  });

  /// Classes (cursus) proposées, et celle affichée.
  final List<SchoolClass> classes;
  final String? selectedClass;

  /// Sélecteurs de classe et de semestre, s'ils existent.
  final FormSelect? classSelect;
  final FormSelect? periodSelect;

  /// Bouton de validation du formulaire (nom, valeur), s'il existe.
  final MapEntry<String, String>? submitButton;

  final List<Grade> grades;

  /// Évaluations annoncées par la page mais non comprises.
  final int unreadable;
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
        unreadable: unreadable,
        classes: classes,
        selectedClass: selectedClass,
      );

  /// Structure de la page, pour le journal de diagnostic : sélecteurs,
  /// choix proposés (★ = affiché), mode de rechargement, bouton. Aucune
  /// note, aucun champ de formulaire, aucun secret.
  String describe() {
    String mode(FormSelect? select) => select == null
        ? 'absent'
        : (select.autoPostBack ? 'rechargement auto' : 'sans rechargement auto');
    final String classList = classes
        .map((SchoolClass c) => '${c.value} « ${c.label} »${c.value == selectedClass ? ' ★' : ''}')
        .join(', ');
    final String periodList = periods
        .map((SchoolPeriod p) => '${p.value} « ${p.label} »${p.value == selectedPeriod ? ' ★' : ''}')
        .join(', ');
    return 'classes [$classList] (${mode(classSelect)}) · '
        'semestres [$periodList] (${mode(periodSelect)}) · '
        'bouton ${submitButton?.key ?? 'absent'} · '
        '${grades.length} note(s), $unreadable illisible(s)';
  }

  /// Champs à poster pour passer [select] à [value], comme le ferait le
  /// navigateur : tout le formulaire, puis soit l'événement du sélecteur
  /// (rechargement automatique), soit un clic sur le bouton de validation.
  Map<String, String> postbackFor(FormSelect select, String value) {
    final Map<String, String> form = Map<String, String>.of(formFields)
      ..[select.name] = value;
    final MapEntry<String, String>? button = submitButton;
    if (select.autoPostBack || button == null) {
      form
        ..['__EVENTTARGET'] = select.name
        ..['__EVENTARGUMENT'] = '';
    } else {
      form
        ..['__EVENTTARGET'] = ''
        ..['__EVENTARGUMENT'] = ''
        ..[button.key] = button.value;
    }
    return form;
  }
}

/// Parsing de la page des notes, formulaire ASP.NET WebForms (§4).
abstract final class GradesParser {
  GradesParser._();

  /// Barème d'une note : « <span>/20</span> », « <span>/10</span> »…
  static const String _scale = r'<span[^>]*>\s*/\s*([\d.,]+)\s*</span>';

  /// Regex d'origine (§4.1 a), ancrée sur des repères sémantiques stables :
  /// note, barème, coefficient, matière, date « du JJ/MM/AAAA », type.
  ///
  /// La note n'est pas forcément un nombre (« ABS », « DISP »…) ni le barème
  /// forcément 20 : rien de ce que l'école affiche ne doit disparaître.
  ///
  /// Chaque `.*?` d'origine est « tempéré » (`_inBlock`) : il ne peut pas
  /// franchir le barème de la note suivante. Un bloc incomplet (sans date,
  /// par exemple) ne fusionne donc jamais avec la note d'après, qui serait
  /// sinon perdue ; coefficient, date et type sont facultatifs.
  static const String _inBlock = r'(?:(?!/\s*[\d.,]+\s*</span>).)*?';
  static final RegExp _gradeBlock = RegExp(
    r'>([^<>]{1,24})</span>\s*'
    '$_scale'
    '(?:$_inBlock'
    r'coeff\.\s*([\d.,]+))?'
    '$_inBlock'
    r'<td[^>]*>\s*<span[^>]*>([^<]+)</span>'
    '(?:$_inBlock'
    r'du\s+(\d{2}/\d{2}/\d{4})[^<]*</span>\s*<span[^>]*>([^<]*)</span>)?',
    dotAll: true,
  );

  /// Indices d'évaluations, indépendants de [_gradeBlock] : s'il y en a plus
  /// que de notes comprises, la page a changé de format.
  static final RegExp _scaleHint = RegExp(_scale);
  static final RegExp _coefficientHint = RegExp(r'coeff\.\s*[\d.,]+');

  static final RegExp _date = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$');
  static final RegExp _spaces = RegExp(r'\s+');

  /// Repère d'une vraie page de notes : le sélecteur de semestre, ou au
  /// moins une note « /20 ». Sans lui, la page n'est pas une page de notes
  /// (même si elle contient un champ mot de passe ailleurs).
  static final RegExp pageMarker =
      RegExp(r'DropDownLstPeriode|>\s*/\s*\d+\s*<');

  /// Lève [DataFailure] si la page n'est pas une page de notes (ni sélecteur
  /// de semestre, ni note), ou si elle annonce des évaluations dont aucune
  /// n'est comprise : le format a changé, et « aucune note » serait un
  /// mensonge. Un semestre réellement sans note reste une page valide.
  static GradesPage parse(String html) {
    final Document document = html_parser.parse(html);
    final Element? select = _periodSelect(document);
    final List<Grade> grades = parseGrades(html);
    if (select == null && grades.isEmpty) {
      throw const DataFailure('La page des notes reçue est illisible.');
    }
    final int unreadable = countUnreadable(html, grades.length);
    if (grades.isEmpty && unreadable > 0) {
      throw const DataFailure(
        'Le format de la page des notes a changé : notes illisibles.',
      );
    }
    final Element? classSelect = _select(document, ScFormConfig.classSelectSuffix);
    return GradesPage(
      grades: grades,
      unreadable: unreadable,
      periods: select == null ? const <SchoolPeriod>[] : _periods(select),
      selectedPeriod: select == null ? null : _selectedValue(select),
      periodFieldName: select?.attributes['name'],
      formFields: extractFormFields(document),
      classes: classSelect == null ? const <SchoolClass>[] : _classes(classSelect),
      selectedClass: classSelect == null ? null : _selectedValue(classSelect),
      classSelect: _formSelect(classSelect),
      periodSelect: _formSelect(select),
      submitButton: _submitButton(document),
    );
  }

  static FormSelect? _formSelect(Element? select) {
    final String? name = select?.attributes['name'];
    if (select == null || name == null || name.isEmpty) return null;
    return FormSelect(
      name: name,
      autoPostBack: (select.attributes['onchange'] ?? '').contains('__doPostBack'),
    );
  }

  /// Bouton « Valider » du formulaire : le premier `submit` nommé.
  static MapEntry<String, String>? _submitButton(Document document) {
    for (final Element input in document.querySelectorAll('input')) {
      final String? name = input.attributes['name'];
      if ((input.attributes['type'] ?? '').toLowerCase() == 'submit' &&
          name != null &&
          name.isNotEmpty &&
          !input.attributes.containsKey('disabled')) {
        return MapEntry<String, String>(name, input.attributes['value'] ?? '');
      }
    }
    return null;
  }

  static Element? _select(Document document, String suffix) => document
      .querySelectorAll('select')
      .where((Element s) => (s.attributes['name'] ?? '').endsWith(suffix))
      .firstOrNull;

  static List<SchoolClass> _classes(Element select) => [
        for (final Element option in select.querySelectorAll('option'))
          if ((option.attributes['value'] ?? '').isNotEmpty)
            SchoolClass(
              value: option.attributes['value']!,
              label: _clean(option.text),
            ),
      ];

  /// Évaluations annoncées par la page (barèmes ou coefficients) au-delà des
  /// [understood] notes comprises.
  static int countUnreadable(String html, int understood) {
    final int scales = _scaleHint.allMatches(html).length;
    final int coefficients = _coefficientHint.allMatches(html).length;
    final int announced = scales > coefficients ? scales : coefficients;
    return announced > understood ? announced - understood : 0;
  }

  static List<Grade> parseGrades(String html) => [
        for (final RegExpMatch m in _gradeBlock.allMatches(html))
          if (_grade(m) case final Grade grade) grade,
      ];

  static Grade? _grade(RegExpMatch m) {
    final String raw = _text(m.group(1)!);
    final double? value = _number(raw);
    final double? outOf = _number(m.group(2)!);
    // Ni nombre ni mention, ou barème absurde : compté comme illisible.
    if (raw.isEmpty || outOf == null || outOf <= 0) return null;
    return Grade(
      value: value,
      mention: value == null ? raw : null,
      outOf: outOf,
      coefficient: _number(m.group(3) ?? '') ?? 1,
      subject: _text(m.group(4)!),
      date: _parseDate(m.group(5) ?? ''),
      type: _optionalText(m.group(6)),
    );
  }

  static String? _optionalText(String? raw) {
    if (raw == null) return null;
    final String text = _text(raw);
    return text.isEmpty ? null : text;
  }

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
