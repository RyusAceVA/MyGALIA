import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/core/presentation/expressive/loading_indicator.dart';
import 'package:mygalia/core/presentation/expressive/material_shapes.dart';
import 'package:mygalia/core/presentation/expressive/shape_badge.dart';
import 'package:mygalia/core/presentation/expressive/wavy_progress_indicator.dart';
import 'package:mygalia/features/grades/domain/grade.dart';
import 'package:mygalia/features/grades/presentation/grades_controller.dart';
import 'package:mygalia/features/grades/presentation/grades_screen.dart';
import 'package:mygalia/features/schedule/domain/course.dart';
import 'package:mygalia/features/schedule/presentation/period_jump_controller.dart';
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

/// Recherche de la période suivante en cours.
class _SearchingJump extends PeriodJumpController {
  @override
  PeriodJumpDirection? build() => PeriodJumpDirection.next;
}

final DateTime _monday = DateTime(2026, 10, 12);
const List<String> _subjects = ['COURS LUN', 'COURS MAR', 'COURS MER', 'COURS JEU', 'COURS VEN'];

WeekSchedule _week({Set<int> emptyDays = const <int>{}}) => WeekSchedule(
      monday: _monday,
      courses: [
        for (int i = 0; i < 5; i++)
          if (!emptyDays.contains(i))
            Course(
              start: DateTime(_monday.year, _monday.month, _monday.day + i, 8, 30),
              end: DateTime(_monday.year, _monday.month, _monday.day + i, 12),
              subject: _subjects[i],
              group: 'TSRS1',
              teachers: 'DEWOLF GIAMMATTEI François',
              room: 'PITON FOURNAISE',
            ),
      ],
    );

/// Planning de la semaine du 12/10/2026, jour choisi : lundi.
List<Override> _schedule(DataState<WeekSchedule> state, {_FakeScheduleController? fake}) => [
      scheduleSelectedDayProvider.overrideWith((ref) => _monday),
      scheduleControllerProvider.overrideWith(() => fake ?? _FakeScheduleController(state)),
    ];

Future<void> _pump(WidgetTester tester, Widget screen, List<Override> overrides) async {
  await tester.pumpWidget(
    ProviderScope(overrides: overrides, child: MaterialApp(home: screen)),
  );
  await tester.pump();
}

void main() {
  testWidgets('planning : séances du jour choisi seulement, date de mise à jour', (tester) async {
    await _pump(
      tester,
      const ScheduleScreen(),
      _schedule(DataSuccess<WeekSchedule>(_week(), DateTime.now())),
    );

    expect(find.textContaining('Mis à jour aujourd\'hui'), findsOneWidget);
    expect(find.text('COURS LUN'), findsOneWidget);
    expect(find.text('COURS MAR'), findsNothing);
    expect(find.text('12 – 16 oct. 2026'), findsOneWidget);
    expect(find.text('Prochains cours'), findsOneWidget);
    expect(find.text('Cours précédents'), findsOneWidget);
  });

  testWidgets('planning en cours de rafraîchissement : indicateur à formes en haut de la liste', (tester) async {
    await _pump(
      tester,
      const ScheduleScreen(),
      _schedule(DataSuccess<WeekSchedule>(_week(), DateTime.now(), isRefreshing: true)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
    expect(find.text('COURS LUN'), findsOneWidget, reason: 'les données restent affichées');
    expect(find.byType(WavyLinearProgressIndicator), findsNothing, reason: 'pas de recherche');
  });

  testWidgets('planning : recherche en cours — vague, formes et bouton « Annuler »', (tester) async {
    await _pump(tester, const ScheduleScreen(), [
      ..._schedule(DataSuccess<WeekSchedule>(_week(), DateTime.now())),
      periodJumpControllerProvider.overrideWith(_SearchingJump.new),
    ]);

    expect(find.text('Annuler'), findsOneWidget);
    expect(find.text('Prochains cours'), findsNothing);
    expect(find.text('Cours précédents'), findsOneWidget);
    expect(find.byType(WavyLinearProgressIndicator), findsOneWidget);
    // Libellé fusionné dans celui du bouton.
    expect(find.bySemanticsLabel(RegExp('Recherche en cours')), findsOneWidget);
  });

  testWidgets('planning : toucher un jour de la bande affiche ses séances', (tester) async {
    await _pump(
      tester,
      const ScheduleScreen(),
      _schedule(DataSuccess<WeekSchedule>(_week(), DateTime.now())),
    );

    await tester.tap(find.text('Mar'));
    await tester.pump();

    expect(find.text('COURS MAR'), findsOneWidget);
    expect(find.text('COURS LUN'), findsNothing);
  });

  testWidgets('planning : jour sans cours, lien vers le prochain cours', (tester) async {
    await _pump(
      tester,
      const ScheduleScreen(),
      _schedule(DataSuccess<WeekSchedule>(_week(emptyDays: {0, 1, 2}), DateTime.now())),
    );

    expect(find.text('Pas de cours ce jour'), findsOneWidget);
    await tester.tap(find.text('Prochain cours : jeudi 15 octobre à 08:30'));
    await tester.pump();

    expect(find.text('COURS JEU'), findsOneWidget);
  });

  testWidgets('planning en erreur : « Réessayer » appelle refresh', (tester) async {
    final DataError<WeekSchedule> error = DataError<WeekSchedule>(NetworkFailure.offline());
    final _FakeScheduleController fake = _FakeScheduleController(error);
    await _pump(tester, const ScheduleScreen(), _schedule(error, fake: fake));

    expect(find.text('Pas de connexion'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pump();

    expect(fake.refreshCalls, 1);
  });

  testWidgets('planning en cache après échec : bandeau d\'avertissement', (tester) async {
    await _pump(
      tester,
      const ScheduleScreen(),
      _schedule(
        DataCached<WeekSchedule>(
          _week(),
          DateTime.now().subtract(const Duration(days: 1)),
          failure: ServerFailure.status(503),
        ),
      ),
    );

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

    expect(find.text('MOYENNE GÉNÉRALE'), findsOneWidget);
    expect(find.text('Meilleure'), findsOneWidget);
    expect(find.text('Plus basse'), findsOneWidget);
    expect(find.text('Toutes les notes'), findsOneWidget);
    expect(find.text('Sensibilisation ITIL'), findsWidgets);
    expect(find.textContaining('12,5'), findsWidgets);
    expect(find.text('coef. 1'), findsOneWidget);
    expect(find.text('19 septembre 2025'), findsOneWidget);
    expect(find.text('SEMESTRE 2'), findsOneWidget);
    expect(find.text('SEMESTRE 1'), findsOneWidget);
  });

  testWidgets('notes : chaque note dans une forme, soleil dès 16 sur 20', (tester) async {
    await _pump(tester, const GradesScreen(), [
      gradesControllerProvider.overrideWith(
        () => _FakeGradesController(
          DataSuccess<GradesSnapshot>(
            GradesSnapshot(
              periods: const [],
              selectedPeriod: null,
              grades: [
                Grade(value: 17, coefficient: 1, subject: 'Réseaux', date: DateTime(2026, 9, 2)),
                Grade(value: 12.5, coefficient: 1, subject: 'Anglais', date: DateTime(2026, 9, 1)),
              ],
            ),
            DateTime.now(),
          ),
        ),
      ),
    ]);

    MaterialShape shapeOf(String subject) => tester
        .widget<ShapeBadge>(
          find.descendant(
            of: find.ancestor(of: find.text(subject), matching: find.byType(GradeTile)).first,
            matching: find.byType(ShapeBadge),
          ),
        )
        .shape;
    expect(shapeOf('Réseaux'), same(MaterialShapes.sunny));
    expect(shapeOf('Anglais'), same(MaterialShapes.cookie9));
    expect(find.text('2 notes'), findsOneWidget);
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
    expect(find.text('Aucune note pour ce semestre.'), findsOneWidget);

    await tester.tap(find.text('SEMESTRE 2'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    final SegmentedButton<String> selector =
        tester.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
    expect(selector.selected, {'31'});
  });

  test('formatNumber : virgule décimale française', () {
    expect(formatNumber(12.5), '12,5');
    expect(formatNumber(12), '12');
    expect(formatNumber(13.25), '13,25');
  });
}
