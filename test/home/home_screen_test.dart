import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/clock.dart';
import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/core/presentation/expressive/material_shapes.dart';
import 'package:mygalia/core/presentation/expressive/shape_badge.dart';
import 'package:mygalia/core/presentation/home_tabs.dart';
import 'package:mygalia/core/storage/secure_storage_service.dart';
import 'package:mygalia/features/grades/domain/grade.dart';
import 'package:mygalia/features/grades/presentation/grades_controller.dart';
import 'package:mygalia/features/home/presentation/home_screen.dart';
import 'package:mygalia/features/schedule/domain/course.dart';
import 'package:mygalia/features/schedule/presentation/schedule_controller.dart';

import '../support/in_memory_secure_store.dart';

class _FakeSchedule extends ScheduleController {
  _FakeSchedule(this.value);

  final DataState<WeekSchedule> value;

  @override
  DataState<WeekSchedule> build(DateTime monday) => value;

  @override
  Future<void> refresh() async {}
}

class _FakeGrades extends GradesController {
  _FakeGrades(this.value);

  final DataState<GradesSnapshot> value;

  @override
  DataState<GradesSnapshot> build(String period) => value;

  @override
  Future<void> refresh() async {}
}

final DateTime _monday = DateTime(2026, 10, 12);

Course _c(int dayOffset, int h1, int m1, int h2, int m2, String subject) => Course(
      start: DateTime(2026, 10, 12 + dayOffset, h1, m1),
      end: DateTime(2026, 10, 12 + dayOffset, h2, m2),
      subject: subject,
      room: 'SALLE 2',
    );

final WeekSchedule _schoolWeek = WeekSchedule(monday: _monday, courses: [
  _c(0, 8, 30, 12, 0, 'DEVELOPPEMENT WEB'),
  _c(0, 13, 30, 16, 30, 'RESEAUX'),
  _c(1, 9, 0, 12, 0, 'ANGLAIS'),
]);

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  required DateTime now,
  required WeekSchedule week,
}) async {
  tester.view
    ..physicalSize = const Size(1080, 4800)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(() => now),
        secureKeyValueStoreProvider.overrideWithValue(InMemorySecureKeyValueStore()),
        scheduleControllerProvider.overrideWith(
          () => _FakeSchedule(DataSuccess<WeekSchedule>(week, now)),
        ),
        gradesControllerProvider.overrideWith(
          () => _FakeGrades(
            DataSuccess<GradesSnapshot>(
              GradesSnapshot(
                periods: const <SchoolPeriod>[],
                selectedPeriod: null,
                grades: [
                  Grade(
                    value: 19.9,
                    coefficient: 1,
                    subject: 'Sauvegarde et restauration',
                    date: DateTime(2026, 8, 5),
                    type: 'Devoir surveillé',
                  ),
                ],
              ),
              now,
            ),
          ),
        ),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pump();
  final ProviderContainer container =
      ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
  // Garde les états d'écran (autoDispose) observables pendant le test.
  container.listen(homeTabProvider, (_, __) {});
  return container;
}

/// Forme de la carte qui contient [text].
MaterialShape _shapeOfCardWith(WidgetTester tester, String text) => tester
    .widget<ShapeBadge>(
      find.descendant(
        of: find.ancestor(of: find.text(text), matching: find.byType(Card)).first,
        matching: find.byType(ShapeBadge),
      ),
    )
    .shape;

void main() {
  testWidgets('pendant un cours : carte « En cours », compteur, planning du jour, notes', (tester) async {
    await _pumpHome(tester, now: DateTime(2026, 10, 12, 10), week: _schoolWeek);

    expect(find.text('Lundi 12 octobre'), findsOneWidget);
    expect(find.text('Bonjour 👋'), findsOneWidget);
    expect(find.text('EN COURS'), findsOneWidget);
    expect(find.text('Se termine dans 2 h'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('cours restants aujourd\'hui'), findsOneWidget);
    expect(find.text('DEVELOPPEMENT WEB'), findsNWidgets(2), reason: 'carte + planning du jour');
    expect(find.text('RESEAUX'), findsOneWidget);
    expect(find.text('Sauvegarde et restauration'), findsOneWidget);
  });

  testWidgets('journée terminée : lien vers le prochain cours de la semaine', (tester) async {
    final ProviderContainer container =
        await _pumpHome(tester, now: DateTime(2026, 10, 12, 17), week: _schoolWeek);

    expect(find.text('Journée terminée'), findsOneWidget);
    expect(find.text('cours restant aujourd\'hui'), findsOneWidget);
    await tester.tap(find.text('Prochain cours : mardi 13 octobre à 09:00 — ANGLAIS'));
    await tester.pump();

    expect(container.read(homeTabProvider), HomeTab.schedule);
    expect(container.read(scheduleSelectedDayProvider), DateTime(2026, 10, 13));
  });

  testWidgets('entreprise toute la semaine : bouton « Trouver les prochains cours »', (tester) async {
    final WeekSchedule company = WeekSchedule(monday: _monday, courses: [
      for (int d = 0; d < 5; d++) _c(d, 8, 30, 12, 0, 'Presence en entreprise'),
    ]);

    await _pumpHome(tester, now: DateTime(2026, 10, 12, 10), week: company);

    expect(find.text('Présence en entreprise'), findsWidgets);
    expect(find.text('Trouver les prochains cours'), findsOneWidget);
  });

  testWidgets('accès rapide : « Mes notes » ouvre l\'onglet Notes', (tester) async {
    final ProviderContainer container =
        await _pumpHome(tester, now: DateTime(2026, 10, 12, 10), week: _schoolWeek);

    await tester.tap(find.text('Mes notes'));
    await tester.pump();

    expect(container.read(homeTabProvider), HomeTab.grades);
  });

  testWidgets('carte principale : éclat pendant un cours', (tester) async {
    await _pumpHome(tester, now: DateTime(2026, 10, 12, 10), week: _schoolWeek);
    expect(_shapeOfCardWith(tester, 'EN COURS'), same(MaterialShapes.softBurst));
  });

  testWidgets('carte principale : trèfle avant le prochain cours', (tester) async {
    await _pumpHome(tester, now: DateTime(2026, 10, 12, 12, 30), week: _schoolWeek);
    expect(_shapeOfCardWith(tester, 'À VENIR'), same(MaterialShapes.clover4));
  });

  testWidgets('carte principale : biscuit en fin de journée', (tester) async {
    await _pumpHome(tester, now: DateTime(2026, 10, 12, 17), week: _schoolWeek);
    expect(_shapeOfCardWith(tester, 'Journée terminée'), same(MaterialShapes.cookie9));
  });

  testWidgets('carte principale : pentagone en entreprise', (tester) async {
    final WeekSchedule company = WeekSchedule(monday: _monday, courses: [
      for (int d = 0; d < 5; d++) _c(d, 8, 30, 12, 0, 'Presence en entreprise'),
    ]);
    await _pumpHome(tester, now: DateTime(2026, 10, 12, 10), week: company);
    expect(_shapeOfCardWith(tester, 'Trouver les prochains cours'), same(MaterialShapes.pentagon));
  });

  testWidgets('l\'initiale du compte ouvre les Paramètres', (tester) async {
    final ProviderContainer container =
        await _pumpHome(tester, now: DateTime(2026, 10, 12, 10), week: _schoolWeek);

    await tester.tap(find.byTooltip('Paramètres'));
    await tester.pump();

    expect(container.read(homeTabProvider), HomeTab.settings);
  });
}
