import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/features/grades/data/grades_parser.dart';
import 'package:mygalia/features/grades/domain/grade.dart';

import '../support/fake_scform_server.dart';

void main() {
  test('notes du bloc HTML des notes de rétro-ingénierie', () {
    final GradesPage page =
        GradesParser.parse(FakeScFormServer.notesPageHtml(period: '30'));

    expect(page.grades, hasLength(2));
    final Grade itil = page.grades.first;
    expect(itil.value, 12.5);
    expect(itil.coefficient, 1);
    expect(itil.subject, 'Sensibilisation ITIL');
    expect(itil.date, DateTime(2025, 9, 19));
    expect(itil.type, 'Devoir surveillé');
    expect(page.grades[1].subject, 'Réseaux', reason: 'entités décodées');
    expect(page.grades[1].type, 'TP noté');
  });

  test('nombres français normalisés (« 15,5 », coeff « 2,00 »)', () {
    final Grade grade =
        GradesParser.parse(FakeScFormServer.notesPageHtml(period: '31')).grades.single;

    expect(grade.value, 15.5);
    expect(grade.coefficient, 2);
  });

  test('semestres et semestre sélectionné', () {
    final GradesPage page =
        GradesParser.parse(FakeScFormServer.notesPageHtml(period: '30'));

    expect(page.periods.map((SchoolPeriod p) => p.value), ['31', '30']);
    expect(page.periods.first.label, 'SEMESTRE 2 (du 29/09/2025 au 11/09/2026)');
    expect(page.selectedPeriod, '30');
    expect(page.periodFieldName, r'ctl00$MainContent$DropDownLstPeriode');
  });

  test('formulaire complet : cachés, select, radio coché, jamais le bouton', () {
    final Map<String, String> form = GradesParser.extractFormFields(
      html_parser.parse(FakeScFormServer.notesPageHtml(period: '30')),
    );

    expect(form['__VIEWSTATE'], FakeScFormServer.viewState);
    expect(form['__VIEWSTATEGENERATOR'], '472C7C7B');
    expect(form['__EVENTVALIDATION'], FakeScFormServer.eventValidation);
    expect(form[r'ctl00$MainContent$DropDownLstClasse'], '17');
    expect(form[r'ctl00$MainContent$DropDownLstPeriode'], '30');
    expect(form[r'ctl00$MainContent$RadioButtonAffichage'], '0');
    expect(form.containsKey(r'ctl00$MainContent$BtnValider'), isFalse);
  });

  test('semestre sans note (sélecteur présent) : page valide et vide', () {
    final GradesPage page = GradesParser.parse(
      '<html><body><form><select name="ctl00\$MainContent\$DropDownLstPeriode">'
      '<option selected="selected" value="32">SEMESTRE 3</option></select>'
      '</form></body></html>',
    );

    expect(page.grades, isEmpty);
    expect(page.selectedPeriod, '32');
  });

  test('page sans sélecteur ni note : DataFailure', () {
    expect(
      () => GradesParser.parse('<html><body><p>Erreur serveur</p></body></html>'),
      throwsA(isA<DataFailure>()),
    );
  });
}
