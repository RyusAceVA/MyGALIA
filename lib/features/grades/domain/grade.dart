import 'package:flutter/foundation.dart';

/// Une note (§4.1 a de la rétro-ingénierie).
@immutable
class Grade {
  const Grade({
    required this.value,
    required this.coefficient,
    required this.subject,
    this.outOf = 20,
    this.date,
    this.type,
  });

  final double value;
  final double outOf;
  final double coefficient;
  final String subject;
  final DateTime? date;

  /// Nature de l'évaluation (« Devoir surveillé », « Oral »…).
  final String? type;

  /// Note ramenée sur 20.
  double get on20 => outOf == 0 ? 0 : value / outOf * 20;

  Map<String, Object?> toJson() => {
        'value': value,
        'outOf': outOf,
        'coefficient': coefficient,
        'subject': subject,
        'date': date?.toIso8601String(),
        'type': type,
      };

  /// Lève une erreur si le contenu est incomplet (cache corrompu).
  static Grade fromJson(Map<String, Object?> json) {
    final Object? date = json['date'];
    return Grade(
      value: (json['value']! as num).toDouble(),
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
      final double on20 = g.on20;
      if (g.coefficient > 0) {
        weighted += on20 * g.coefficient;
        coefficients += g.coefficient;
      }
      if (best == null || on20 > best.on20) best = g;
      if (worst == null || on20 < worst.on20) worst = g;
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
  });

  final List<SchoolPeriod> periods;

  /// Valeur du semestre affiché (`null` si la page n'a pas de sélecteur).
  final String? selectedPeriod;
  final List<Grade> grades;

  Map<String, Object?> toJson() => {
        'periods': [for (final SchoolPeriod p in periods) p.toJson()],
        'selectedPeriod': selectedPeriod,
        'grades': [for (final Grade g in grades) g.toJson()],
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
      );
}
