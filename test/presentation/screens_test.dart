import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/features/grades/domain/grade.dart';
import 'package:mygalia/features/grades/presentation/grades_controller.dart';
import 'package:mygalia/features/grades/presentation/grades_screen.dart';
import 'package:mygalia/features/schedule/domain/course.dart';
import 'package:mygalia/features/schedule/presentation/schedule_controller.dart';
import 'package:mygalia/features/schedule/presentation/schedule_screen.dart';

class _FakeScheduleController extends ScheduleController {
  _FakeScheduleController(this.initial);

  final DataState<WeekSchedule> initial;
  int refreshCalls = 0;

  @override
  DataState<WeekSchedule> build(DateTime monday) => initial;

  @override
  Future<void> refresh() async => refreshCalls++;
}

class _FakeGradesController extends GradesController {
  _FakeGradesController(this.initial);

  final DataState<GradesSnapshot> initial;

  @override
  DataState<GradesSnapshot> build(String period) => initial;

  @override
  Future<void> refresh() async {}
}

/// Un état par semestre (clé = valeur du semestre, '' = courant).
class _FakeGradesControllerByPeriod extends GradesController {
  _FakeGradesControllerByPeriod(this.states);

  final Map<String, DataState<GradesSnapshot>> states;

  @override
  DataState<GradesSnapshot> build(String period) =>
      states[period] ?? const DataLoading<GradesSnapshot>();

  @override
  Future<void> refresh() async {}
}

WeekSchedule _week() {
  final DateTime monday = mondayOf(DateTime.now());
  return WeekSchedule(
    monday: monday,
    courses: [
      for (int i = 0; i < 5; i++)
        Course(
          start: DateTime(monday.year, monday.month, monday.day + i, 8, 30),
          end: DateTime(monday.year, monday.month, monday.day + i, 12),
          subject: 'DEVELOPPEMENT WEB',
          group: 'TSRS1',
          teachers: 'DEWOLF GIAMMATTEI François',
          room: 'PITON FOURNAISE',
        ),
    ],
  );
}

Future<void> _pump(WidgetTester tester, Widget screen, List<Override> overrides) async {
  await tester.pumpWidget(
    ProviderScope(overrides: overrides, child: MaterialApp(home: screen)),
  );
  await tester.pump();
}

void main() {
  testWidgets('planning : séances, date de mise à jour', (tester) async {
    await _pump(tester, const ScheduleScreen(), [
      scheduleControllerProvider.overrideWith(
        () => _FakeScheduleController(DataSuccess<WeekSchedule>(_week(), DateTime.now())),
      ),
    ]);

    expect(find.textContaining('Mis à jour aujourd\'hui'), findsOneWidget);
    expect(find.text('DEVELOPPEMENT WEB'), findsWidgets);
  });

  testWidgets('planning en erreur : « Réessayer » appelle refresh', (tester) async {
    final _FakeScheduleController fake = _FakeScheduleController(
      DataError<WeekSchedule>(NetworkFailure.offline()),
    );
    await _pump(tester, const ScheduleScreen(), [
      scheduleControllerProvider.overrideWith(() => fake),
    ]);

    expect(find.text('Pas de connexion'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pump();

    expect(fake.refreshCalls, 1);
  });

  testWidgets('planning en cache après échec : bandeau d\'avertissement', (tester) async {
    await _pump(tester, const ScheduleScreen(), [
      scheduleControllerProvider.overrideWith(
        () => _FakeScheduleController(
          DataCached<WeekSchedule>(
            _week(),
            DateTime.now().subtract(const Duration(days: 1)),
            failure: ServerFailure.status(503),
          ),
        ),
      ),
    ]);

    expect(find.text('Rafraîchissement impossible'), findsOneWidget);
    expect(find.textContaining('hier à'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('notes : note, barème, coefficient et sélecteur de semestre', (tester) async {
    await _pump(tester, const GradesScreen(), [
      gradesControllerProvider.overrideWith(
        () => _FakeGradesController(
          DataSuccess<GradesSnapshot>(
            GradesSnapshot(
              periods: const [
                SchoolPeriod(value: '31', label: 'SEMESTRE 2 (du 29/09/2025 au 11/09/2026)'),
                SchoolPeriod(value: '30', label: 'SEMESTRE 1 (du 16/09/2024 au 19/09/2025)'),
              ],
              selectedPeriod: '30',
              grades: [
                Grade(
                  value: 12.5,
                  coefficient: 1,
                  subject: 'Sensibilisation ITIL',
                  date: DateTime(2025, 9, 19),
                  type: 'Devoir surveillé',
                ),
              ],
            ),
            DateTime.now(),
          ),
        ),
      ),
    ]);

    expect(find.text('Sensibilisation ITIL'), findsOneWidget);
    expect(find.textContaining('12,5'), findsOneWidget);
    expect(find.text('coef. 1'), findsOneWidget);
    expect(find.text('Semestre'), findsWidgets);
  });

  testWidgets('notes : le sélecteur reste visible pendant le changement de semestre', (tester) async {
    const List<SchoolPeriod> periods = [
      SchoolPeriod(value: '31', label: 'SEMESTRE 2 (du 29/09/2025 au 11/09/2026)'),
      SchoolPeriod(value: '30', label: 'SEMESTRE 1 (du 16/09/2024 au 19/09/2025)'),
    ];
    await _pump(tester, const GradesScreen(), [
      gradesControllerProvider.overrideWith(
        () => _FakeGradesControllerByPeriod({
          '': DataSuccess<GradesSnapshot>(
            const GradesSnapshot(periods: periods, selectedPeriod: '30', grades: []),
            DateTime.now(),
          ),
          '31': const DataLoading<GradesSnapshot>(),
        }),
      ),
    ]);
    expect(find.text('SEMESTRE 1 (2024-2025)'), findsWidgets);

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SEMESTRE 2 (du 29/09/2025 au 11/09/2026)').last);
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(DropdownMenu<String>), findsOneWidget);
    expect(find.text('SEMESTRE 2 (2025-2026)'), findsWidgets);
  });

  test('formatNumber : virgule décimale française', () {
    expect(formatNumber(12.5), '12,5');
    expect(formatNumber(12), '12');
    expect(formatNumber(13.25), '13,25');
  });
}
