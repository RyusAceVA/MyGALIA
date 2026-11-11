import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/features/schedule/data/calendar_exporter.dart';
import 'package:mygalia/features/schedule/domain/course.dart';
import 'package:mygalia/features/schedule/presentation/schedule_controller.dart';
import 'package:mygalia/features/schedule/presentation/schedule_screen.dart';

class _FixedSchedule extends ScheduleController {
  _FixedSchedule(this.initial);

  final DataState<WeekSchedule> initial;

  @override
  DataState<WeekSchedule> build(DateTime monday) => initial;

  @override
  Future<void> refresh() async {}
}

void main() {
  Future<List<WeekSchedule>> pump(
    WidgetTester tester,
    DataState<WeekSchedule> state,
    CalendarExportResult result,
  ) async {
    final List<WeekSchedule> exported = <WeekSchedule>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleControllerProvider.overrideWith(() => _FixedSchedule(state)),
          calendarExporterProvider.overrideWithValue((WeekSchedule week) async {
            exported.add(week);
            return result;
          }),
        ],
        child: const MaterialApp(home: ScheduleScreen()),
      ),
    );
    return exported;
  }

  final DateTime monday = mondayOf(weekdayOnOrAfter(DateTime.now()));
  final WeekSchedule week = WeekSchedule(
    monday: monday,
    courses: [
      Course(
        start: monday.add(const Duration(hours: 8)),
        end: monday.add(const Duration(hours: 12)),
        subject: 'DEVELOPPEMENT WEB',
      ),
    ],
  );

  testWidgets('le bouton remet la semaine affichée à l\'exportateur', (tester) async {
    final List<WeekSchedule> exported = await pump(
      tester,
      DataSuccess<WeekSchedule>(week, DateTime.now()),
      CalendarExportResult.shared,
    );

    await tester.tap(find.byTooltip("Exporter la semaine vers l'agenda"));
    await tester.pump();

    expect(exported.single.monday, monday);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('semaine sans cours : message, pas de partage vide', (tester) async {
    await pump(
      tester,
      DataSuccess<WeekSchedule>(week, DateTime.now()),
      CalendarExportResult.nothingToExport,
    );

    await tester.tap(find.byTooltip("Exporter la semaine vers l'agenda"));
    await tester.pump();

    expect(find.text('Aucun cours à exporter cette semaine.'), findsOneWidget);
  });

  testWidgets('planning pas encore chargé : message, exportateur non appelé',
      (tester) async {
    final List<WeekSchedule> exported = await pump(
      tester,
      const DataLoading<WeekSchedule>(),
      CalendarExportResult.shared,
    );

    await tester.tap(find.byTooltip("Exporter la semaine vers l'agenda"));
    await tester.pump();

    expect(exported, isEmpty);
    expect(find.textContaining('pas encore chargé'), findsOneWidget);
  });
}
