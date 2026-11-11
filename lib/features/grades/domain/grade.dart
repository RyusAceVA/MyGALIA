import 'package:flutter/foundation.dart';

/// Une note (§4.1 a de la rétro-ingénierie).
@immutable
class Grade {
  const Grade({
    this.value,
    required this.coefficient,
    required this.subject,
    this.outOf = 20,
    this.date,
    this.type,
    this.mention,
  }) : assert(value != null || mention != null, 'note ou mention requise');

  /// Note chiffrée ; `null` pour une évaluation sans note (voir [mention]).
  final double? value;

  /// Barème de la note (« /20 », « /10 »…).
  final double outOf;
  final double coefficient;
  final String subject;
  final DateTime? date;

  /// Nature de l'évaluation (« Devoir surveillé », « Oral »…).
  final String? type;

  /// Ce que l'école a écrit à la place d'une note chiffrée (« ABS »,
  /// « DISP »…). Une telle évaluation est affichée mais ne compte dans
  /// aucune moyenne.
  final String? mention;

  /// Note ramenée sur 20 ; `null` sans note chiffrée.
  double? get on20 {
    final double? v = value;
    return v == null || outOf <= 0 ? null : v / outOf * 20;
  }

  Map<String, Object?> toJson() => {
        'value': value,
        'outOf': outOf,
        'coefficient': coefficient,
        'subject': subject,
        'date': date?.toIso8601String(),
        'type': type,
        'mention': mention,
      };

  /// Lève une erreur si le contenu est incomplet (cache corrompu).
  static Grade fromJson(Map<String, Object?> json) {
    final Object? date = json['date'];
    final String? mention = json['mention'] as String?;
    final num? value = json['value'] as num?;
    if (value == null && mention == null) {
      throw const FormatException('note sans valeur ni mention');
    }
    return Grade(
      value: value?.toDouble(),
      mention: mention,
      outOf: (json['outOf']! as num).toDouble(),
      coefficient: (json['coefficient']! as num).toDouble(),
      subject: json['subject']! as String,
      date: date is String ? DateTime.parse(date) : null,
      type: json['type'] as String?,
    );
  }
}

/// Un semestre proposé par le sélecteur de période (§4.1 b).
@immutable
class SchoolPeriod {
  const SchoolPeriod({required this.value, required this.label});

  /// Valeur WebForms (ex. « 30 », « 31 »).
  final String value;

  /// Libellé affiché (« SEMESTRE 1 (du 16/09/2024 au 19/09/2025) »).
  final String label;

  static final RegExp _dates = RegExp(
    r'^(.*?)\s*\(\s*du\s+\d{1,2}/\d{1,2}/(\d{4})\s+au\s+\d{1,2}/\d{1,2}/(\d{4})\s*\)\s*$',
  );

  /// Libellé court pour un champ étroit : « SEMESTRE 1 (2024-2025) ».
  String get shortLabel {
    final Match? m = _dates.firstMatch(label);
    return m == null ? label : '${m.group(1)} (${m.group(2)}-${m.group(3)})';
  }

  static final RegExp _parenthesis = RegExp(r'\s*\(.*\)\s*$');

  /// Nom seul, pour un segment : « SEMESTRE 1 ».
  String get name {
    final String stripped = label.replaceFirst(_parenthesis, '');
    return stripped.isEmpty ? label : stripped;
  }

  Map<String, Object?> toJson() => {'value': value, 'label': label};

  static SchoolPeriod fromJson(Map<String, Object?> json) => SchoolPeriod(
        value: json['value']! as String,
        label: json['label']! as String,
      );

  @override
  bool operator ==(Object other) =>
      other is SchoolPeriod && other.value == value && other.label == label;

  @override
  int get hashCode => Object.hash(value, label);
}

/// Synthèse d'un ensemble de notes (écran Notes, accueil).
@immutable
class GradeStats {
  const GradeStats._(this.average, this.best, this.worst, this.byDate);

  factory GradeStats.of(List<Grade> grades) {
    double weighted = 0;
    double coefficients = 0;
    Grade? best;
    Grade? worst;
    for (final Grade g in grades) {
      // Absence, dispense… : listée, mais hors moyenne et hors extrêmes.
      final double? on20 = g.on20;
      if (on20 == null) continue;
      if (g.coefficient > 0) {
        weighted += on20 * g.coefficient;
        coefficients += g.coefficient;
      }
      if (best == null || on20 > best.on20!) best = g;
      if (worst == null || on20 < worst.on20!) worst = g;
    }
    final List<Grade> byDate = List<Grade>.of(grades);
    // Tri stable (List.sort ne l'est pas) : du plus récent au plus ancien,
    // notes sans date à la fin, ordre de la page sinon.
    final Map<Grade, int> order = {for (int i = 0; i < grades.length; i++) grades[i]: i};
    byDate.sort((Grade a, Grade b) {
      final DateTime? da = a.date;
      final DateTime? db = b.date;
      if (da != null && db != null && da != db) return db.compareTo(da);
      if (da == null && db != null) return 1;
      if (da != null && db == null) return -1;
      return order[a]!.compareTo(order[b]!);
    });
    return GradeStats._(
      coefficients == 0 ? null : weighted / coefficients,
      best,
      worst,
      byDate,
    );
  }

  /// Moyenne pondérée par les coefficients, sur 20 (`null` sans note).
  final double? average;
  final Grade? best;
  final Grade? worst;

  /// Notes de la plus récente à la plus ancienne (sans date : à la fin).
  final List<Grade> byDate;
}

/// Notes d'un semestre et semestres disponibles.
@immutable
class GradesSnapshot {
  const GradesSnapshot({
    required this.periods,
    required this.selectedPeriod,
    required this.grades,
    this.unreadable = 0,
  });

  final List<SchoolPeriod> periods;

  /// Valeur du semestre affiché (`null` si la page n'a pas de sélecteur).
  final String? selectedPeriod;
  final List<Grade> grades;

  /// Évaluations présentes sur la page mais non comprises (format inconnu) :
  /// la moyenne affichée peut alors être incomplète.
  final int unreadable;

  Map<String, Object?> toJson() => {
        'periods': [for (final SchoolPeriod p in periods) p.toJson()],
        'selectedPeriod': selectedPeriod,
        'grades': [for (final Grade g in grades) g.toJson()],
        'unreadable': unreadable,
      };

  static GradesSnapshot fromJson(Map<String, Object?> json) => GradesSnapshot(
        periods: [
          for (final Object? p in json['periods']! as List<Object?>)
            SchoolPeriod.fromJson((p! as Map<Object?, Object?>).cast<String, Object?>()),
        ],
        selectedPeriod: json['selectedPeriod'] as String?,
        grades: [
          for (final Object? g in json['grades']! as List<Object?>)
            Grade.fromJson((g! as Map<Object?, Object?>).cast<String, Object?>()),
        ],
        unreadable: (json['unreadable'] as num?)?.toInt() ?? 0,
      );
}
