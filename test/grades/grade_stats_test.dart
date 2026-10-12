import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/features/grades/domain/grade.dart';

Grade _g(double value, {double coef = 1, DateTime? date, String subject = 'X', double outOf = 20}) =>
    Grade(value: value, coefficient: coef, subject: subject, date: date, outOf: outOf);

void main() {
  test('moyenne pondérée par les coefficients', () {
    final GradeStats stats = GradeStats.of([
      _g(19.9),
      _g(13.3),
      _g(18, coef: 2),
    ]);

    expect(stats.average, closeTo((19.9 + 13.3 + 36) / 4, 1e-9));
  });

  test('barème différent de 20 : ramené sur 20', () {
    final GradeStats stats = GradeStats.of([_g(8, outOf: 10), _g(10)]);

    expect(stats.average, 13);
    expect(stats.best?.value, 8);
  });

  test('meilleure et plus basse note', () {
    final GradeStats stats = GradeStats.of([
      _g(13.3, subject: 'Communication'),
      _g(19.9, subject: 'Sauvegarde et restauration'),
      _g(16, subject: 'Python'),
    ]);

    expect(stats.best?.subject, 'Sauvegarde et restauration');
    expect(stats.worst?.subject, 'Communication');
  });

  test('tri du plus récent au plus ancien, notes sans date à la fin', () {
    final GradeStats stats = GradeStats.of([
      _g(1, date: DateTime(2026, 6, 26), subject: 'juin'),
      _g(2, subject: 'sans date'),
      _g(3, date: DateTime(2026, 8, 5), subject: 'août'),
      _g(4, date: DateTime(2026, 7, 3), subject: 'juillet'),
    ]);

    expect(stats.byDate.map((Grade g) => g.subject), ['août', 'juillet', 'juin', 'sans date']);
  });

  test('aucune note ou coefficients nuls : moyenne absente', () {
    expect(GradeStats.of(const <Grade>[]).average, isNull);
    expect(GradeStats.of([_g(12, coef: 0)]).average, isNull);
  });

  test('nom court du semestre pour un segment', () {
    expect(
      const SchoolPeriod(value: '31', label: 'SEMESTRE 2 (du 29/09/2025 au 11/09/2026)').name,
      'SEMESTRE 2',
    );
    expect(const SchoolPeriod(value: '1', label: 'ANNÉE').name, 'ANNÉE');
  });
}
