import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/features/grades/data/grades_parser.dart';
import 'package:mygalia/features/grades/domain/grade.dart';

/// Ligne de note au format observé, avec note et barème libres.
String _row(String value, String scale, String subject) => '''
<tr><td><span style="font-weight:bold;">$value</span> <span>/$scale</span>
<span style="font-size:9px;">coeff. 1,00</span>
</td><td style="padding-left:3px;">
  <span style="font-size:13px;">$subject</span>
  <span style="font-size:11px;">REF          du 03/06/2025</span>
  <span style="font-size:9px;">Devoir</span>
</td></tr>''';

String _page(String rows) => '''
<html><body><form>
<select name="ctl00\$MainContent\$DropDownLstPeriode">
<option selected="selected" value="30">SEMESTRE 1</option></select>
<table>$rows</table></form></body></html>''';

void main() {
  test('une note sur 10 est gardée et ramenée sur 20', () {
    final Grade grade = GradesParser.parse(_page(_row('7,5', '10', 'Anglais'))).grades.single;

    expect(grade.value, 7.5);
    expect(grade.outOf, 10);
    expect(grade.on20, 15);
  });

  test('une absence est listée, sans note ni effet sur la moyenne', () {
    final GradesPage page = GradesParser.parse(
      _page(_row('ABS', '20', 'Réseaux') + _row('12', '20', 'Anglais')),
    );

    expect(page.grades, hasLength(2));
    expect(page.unreadable, 0);
    final Grade absence = page.grades.first;
    expect(absence.value, isNull);
    expect(absence.mention, 'ABS');
    expect(absence.on20, isNull);

    final GradeStats stats = GradeStats.of(page.grades);
    expect(stats.average, 12);
    expect(stats.best!.subject, 'Anglais');
    expect(stats.worst!.subject, 'Anglais');
    expect(stats.byDate, hasLength(2));
  });

  test('uniquement des mentions : pas de moyenne, pas d\'erreur', () {
    final GradeStats stats =
        GradeStats.of(GradesParser.parse(_page(_row('DISP', '20', 'Sport'))).grades);

    expect(stats.average, isNull);
    expect(stats.best, isNull);
  });

  test('format changé : des barèmes mais aucune note comprise → erreur', () {
    const String changed = '<div class="note"><span>12</span><span>/20</span>'
        '<p>Anglais</p></div>';

    expect(
      () => GradesParser.parse(_page(changed)),
      throwsA(isA<DataFailure>()),
    );
  });

  test('format partiellement changé : notes lues et compte des illisibles', () {
    const String odd = '<div><span>9</span><span>/20</span><p>Sport</p></div>';

    final GradesPage page = GradesParser.parse(_page(_row('12', '20', 'Anglais') + odd));

    expect(page.grades.single.subject, 'Anglais');
    expect(page.unreadable, 1);
    expect(page.toSnapshot().unreadable, 1);
  });

  test('semestre réellement vide : page valide, rien d\'illisible', () {
    final GradesPage page = GradesParser.parse(_page(''));

    expect(page.grades, isEmpty);
    expect(page.unreadable, 0);
  });

  test('cache : mention, barème et compteur survivent à l\'aller-retour', () {
    const GradesSnapshot snapshot = GradesSnapshot(
      periods: <SchoolPeriod>[],
      selectedPeriod: null,
      unreadable: 2,
      grades: [
        Grade(coefficient: 1, subject: 'Réseaux', mention: 'ABS'),
        Grade(value: 7, outOf: 10, coefficient: 2, subject: 'Anglais'),
      ],
    );

    final GradesSnapshot back = GradesSnapshot.fromJson(snapshot.toJson());

    expect(back.unreadable, 2);
    expect(back.grades.first.mention, 'ABS');
    expect(back.grades.first.value, isNull);
    expect(back.grades.last.outOf, 10);
  });

  test('cache d\'avant (sans mention ni compteur) toujours lisible', () {
    final GradesSnapshot old = GradesSnapshot.fromJson({
      'periods': <Object?>[],
      'selectedPeriod': null,
      'grades': [
        {'value': 12.0, 'outOf': 20.0, 'coefficient': 1.0, 'subject': 'Anglais', 'date': null, 'type': null},
      ],
    });

    expect(old.grades.single.value, 12);
    expect(old.unreadable, 0);
  });
}
