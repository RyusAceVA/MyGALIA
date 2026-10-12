import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/features/schedule/data/schedule_parser.dart';
import 'package:mygalia/features/schedule/domain/course.dart';

String _page(List<String> titles) => '<html><body><table><tr>'
    '${titles.map((String t) => '<td><div class="Bouton_Info" title="$t">x</div></td>').join()}'
    '</tr></table></body></html>';

void main() {
  test('séance complète des notes (entités HTML décodées)', () {
    final List<Course> courses = ScheduleParser.parseDay(_page([
      'Le 01/07/2026 de 08:30 &#224; 12:00 (03h30)&#13;&#10;TSRS1&#13;&#10;'
          'DEVELOPPEMENT WEB&#13;&#10;DEWOLF GIAMMATTEI Fran&#231;ois&#13;&#10;'
          'PITON FOURNAISE',
    ]));

    expect(courses, hasLength(1));
    final Course c = courses.single;
    expect(c.start, DateTime(2026, 7, 1, 8, 30));
    expect(c.end, DateTime(2026, 7, 1, 12));
    expect(c.group, 'TSRS1');
    expect(c.subject, 'DEVELOPPEMENT WEB');
    expect(c.teachers, 'DEWOLF GIAMMATTEI François');
    expect(c.room, 'PITON FOURNAISE');
  });

  test('doublons (rowspan) dédupliqués, créneaux vides écartés, tri par heure', () {
    const String afternoon = 'Le 01/07/2026 de 13:30 &#224; 16:30 (03h00)&#10;'
        'TSRS1&#10;ANGLAIS&#10;SMITH John&#10;SALLE 2';
    const String morning = 'Le 01/07/2026 de 08:30 &#224; 12:00 (03h30)&#10;'
        'TSRS1&#10;RESEAUX&#10;DUPONT Marie&#10;SALLE 1';

    final List<Course> courses =
        ScheduleParser.parseDay(_page([afternoon, afternoon, '', morning]));

    expect(courses.map((Course c) => c.subject), ['RESEAUX', 'ANGLAIS']);
  });

  test('format réduit sans groupe : matière, formateur, salle', () {
    final Course? c = ScheduleParser.parseTitle(
      'Le 02/07/2026 de 09:00 à 10:00 (01h00)\nDEVELOPPEMENT WEB\nDUPONT Marie\nSALLE 3',
    );

    expect(c?.group, isNull);
    expect(c?.subject, 'DEVELOPPEMENT WEB');
    expect(c?.teachers, 'DUPONT Marie');
    expect(c?.room, 'SALLE 3');
  });

  test('format réduit sans salle : groupe, matière, formateur', () {
    final Course? c = ScheduleParser.parseTitle(
      'Le 02/07/2026 de 09:00 à 10:00 (01h00)\nTSRS1\nANGLAIS\nSMITH John',
    );

    expect(c?.group, 'TSRS1');
    expect(c?.subject, 'ANGLAIS');
    expect(c?.teachers, 'SMITH John');
    expect(c?.room, isNull);
  });

  test('plusieurs formateurs sur plusieurs lignes', () {
    final Course? c = ScheduleParser.parseTitle(
      'Le 02/07/2026 de 09:00 à 12:00 (03h00)\nTSRS1\nPROJET\nDUPONT Marie\nSMITH John\nSALLE 3',
    );

    expect(c?.teachers, 'DUPONT Marie, SMITH John');
    expect(c?.room, 'SALLE 3');
  });

  test('séance sans matière : écartée', () {
    expect(ScheduleParser.parseTitle('Le 02/07/2026 de 09:00 à 10:00 (01h00)'), isNull);
  });

  test("jour sans cours : liste vide (page valide, donc cachable)", () {
    expect(
      ScheduleParser.parseDay('<html><body><table></table></body></html>'),
      isEmpty,
    );
  });

  test('contenu corrompu (pas du HTML) : DataFailure', () {
    expect(
      () => ScheduleParser.parseDay('{"error":"oops"}'),
      throwsA(isA<DataFailure>()),
    );
  });

  test('séances présentes mais toutes illisibles : DataFailure (format changé)', () {
    expect(
      () => ScheduleParser.parseDay(_page(['Cours de 8h à midi'])),
      throwsA(isA<DataFailure>()),
    );
  });

  test('repli si la classe Bouton_Info disparaît', () {
    const String html = '<html><body>'
        '<span class="NouveauStyle" title="Le 03/07/2026 de 10:00 &#224; 11:00 (01h00)&#10;'
        'TSRS1&#10;MATHS&#10;MARTIN Paul&#10;SALLE 4">x</span></body></html>';

    expect(ScheduleParser.parseDay(html).single.subject, 'MATHS');
  });

  group('repère de page de planning (jour sans cours compris)', () {
    final DateTime day = DateTime(2026, 10, 12);
    final Pattern marker = ScheduleParser.pageMarker(day);

    test('reconnu : grille vide, liens de navigation, date courte ou longue', () {
      for (final String page in [
        '<div class="Bouton_Info" title=""></div>',
        '<a href="/PlanningWeb/PlanningJournalier/Stagiaire?id=1&Jour=13">›</a>',
        '<h2>Planning du 12/10/2026</h2>',
        '<h2>Lundi 12 octobre 2026</h2>',
      ]) {
        expect('<html><body>$page</body></html>'.contains(marker), isTrue, reason: page);
      }
    });

    test('absent : page d\'erreur, autre jour', () {
      for (final String page in [
        '<h1>Une erreur est survenue</h1>',
        '<p>Planning du 112/10/2026</p>',
        '<p>Planning du 13/10/2026</p>',
      ]) {
        expect('<html><body>$page</body></html>'.contains(marker), isFalse, reason: page);
      }
    });
  });

  test('mondayOf : lundi de la semaine, y compris le dimanche', () {
    expect(mondayOf(DateTime(2026, 10, 12)), DateTime(2026, 10, 12));
    expect(mondayOf(DateTime(2026, 10, 18, 23, 59)), DateTime(2026, 10, 12));
    expect(mondayOf(DateTime(2026, 11, 1)), DateTime(2026, 10, 26));
  });
}
