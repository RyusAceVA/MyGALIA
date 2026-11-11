import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/features/grades/domain/grade.dart';
import 'package:mygalia/features/grades/presentation/grades_controller.dart';
import 'package:mygalia/features/grades/presentation/grades_screen.dart';

/// Un état par clé de contrôleur (voir `gradesKey`).
class _GradesByKey extends GradesController {
  _GradesByKey(this.states);

  final Map<String, DataState<GradesSnapshot>> states;

  @override
  DataState<GradesSnapshot> build(String key) =>
      states[key] ?? const DataLoading<GradesSnapshot>();

  @override
  Future<void> refresh() async {}
}

const List<SchoolClass> _classes = [
  SchoolClass(value: '23', label: 'BSRC1'),
  SchoolClass(value: '17', label: 'TSRS1'),
];

Grade _grade(String subject) => Grade(value: 12, coefficient: 1, subject: subject);

void main() {
  group('écran', () {
    Future<void> pump(
      WidgetTester tester,
      Map<String, DataState<GradesSnapshot>> states,
    ) =>
        tester.pumpWidget(
          ProviderScope(
            overrides: [
              gradesControllerProvider.overrideWith(() => _GradesByKey(states)),
            ],
            child: const MaterialApp(home: GradesScreen()),
          ),
        );

    testWidgets('un seul cursus : pas de sélecteur de cursus', (tester) async {
      await pump(tester, {
        '': DataSuccess<GradesSnapshot>(
          GradesSnapshot(
            classes: const [SchoolClass(value: '17', label: 'TSRS1')],
            selectedClass: '17',
            periods: const [SchoolPeriod(value: '30', label: 'SEMESTRE 1')],
            selectedPeriod: '30',
            grades: [_grade('Anglais')],
          ),
          DateTime.now(),
        ),
      });

      expect(find.text('TSRS1'), findsNothing);
      expect(find.text('SEMESTRE 1'), findsOneWidget);
    });

    testWidgets('deux cursus : choisir l\'ancien affiche ses semestres et ses notes',
        (tester) async {
      await pump(tester, {
        '': DataSuccess<GradesSnapshot>(
          GradesSnapshot(
            classes: _classes,
            selectedClass: '23',
            periods: const [
              SchoolPeriod(value: '40', label: 'SEMESTRE 1 (du 14/09/2026 au 10/09/2027)'),
            ],
            selectedPeriod: '40',
            grades: [_grade('Cloud')],
          ),
          DateTime.now(),
        ),
        '17|': DataSuccess<GradesSnapshot>(
          GradesSnapshot(
            classes: _classes,
            selectedClass: '17',
            periods: const [
              SchoolPeriod(value: '31', label: 'SEMESTRE 2 (du 29/09/2025 au 11/09/2026)'),
              SchoolPeriod(value: '30', label: 'SEMESTRE 1 (du 16/09/2024 au 19/09/2025)'),
            ],
            selectedPeriod: '30',
            grades: [_grade('Réseaux')],
          ),
          DateTime.now(),
        ),
        '17|31': DataSuccess<GradesSnapshot>(
          GradesSnapshot(
            classes: _classes,
            selectedClass: '17',
            periods: const [
              SchoolPeriod(value: '31', label: 'SEMESTRE 2 (du 29/09/2025 au 11/09/2026)'),
              SchoolPeriod(value: '30', label: 'SEMESTRE 1 (du 16/09/2024 au 19/09/2025)'),
            ],
            selectedPeriod: '31',
            grades: [_grade('Anglais technique')],
          ),
          DateTime.now(),
        ),
      });

      expect(find.text('BSRC1'), findsOneWidget);
      expect(find.text('TSRS1'), findsOneWidget);
      expect(find.text('Cloud'), findsWidgets);

      await tester.tap(find.text('TSRS1'));
      await tester.pumpAndSettle();

      expect(find.text('Réseaux'), findsWidgets);
      expect(find.text('Cloud'), findsNothing);
      expect(find.text('SEMESTRE 2'), findsOneWidget);

      await tester.tap(find.text('SEMESTRE 2'));
      await tester.pumpAndSettle();

      expect(find.text('Anglais technique'), findsWidgets);
    });

    testWidgets('nouveau cursus : choisir un semestre fige le cursus affiché',
        (tester) async {
      final GradesSnapshot current = GradesSnapshot(
        classes: _classes,
        selectedClass: '23',
        periods: const [
          SchoolPeriod(value: '41', label: 'SEMESTRE 2'),
          SchoolPeriod(value: '40', label: 'SEMESTRE 1'),
        ],
        selectedPeriod: '40',
        grades: [_grade('Cloud')],
      );
      await pump(tester, {
        '': DataSuccess<GradesSnapshot>(current, DateTime.now()),
        '23|41': DataSuccess<GradesSnapshot>(
          GradesSnapshot(
            classes: _classes,
            selectedClass: '23',
            periods: current.periods,
            selectedPeriod: '41',
            grades: [_grade('Sécurité')],
          ),
          DateTime.now(),
        ),
      });

      await tester.tap(find.text('SEMESTRE 2'));
      await tester.pumpAndSettle();

      expect(find.text('Sécurité'), findsWidgets);
    });

    testWidgets('deux semestres de même nom : les années les distinguent',
        (tester) async {
      await pump(tester, {
        '': DataSuccess<GradesSnapshot>(
          GradesSnapshot(
            periods: const [
              SchoolPeriod(value: '40', label: 'SEMESTRE 1 (du 14/09/2026 au 10/09/2027)'),
              SchoolPeriod(value: '30', label: 'SEMESTRE 1 (du 16/09/2024 au 19/09/2025)'),
            ],
            selectedPeriod: '40',
            grades: [_grade('Cloud')],
          ),
          DateTime.now(),
        ),
      });

      expect(find.text('SEMESTRE 1 (2026-2027)'), findsOneWidget);
      expect(find.text('SEMESTRE 1 (2024-2025)'), findsOneWidget);
    });
  });
}
