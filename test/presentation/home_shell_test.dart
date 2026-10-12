import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/clock.dart';
import 'package:mygalia/core/lifecycle/app_lifecycle_watcher.dart';
import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/core/presentation/home_shell.dart';
import 'package:mygalia/core/settings/theme_mode_controller.dart';
import 'package:mygalia/core/storage/secure_storage_service.dart';
import 'package:mygalia/features/grades/domain/grade.dart';
import 'package:mygalia/features/grades/presentation/grades_controller.dart';
import 'package:mygalia/features/schedule/domain/course.dart';
import 'package:mygalia/features/schedule/presentation/schedule_controller.dart';

import '../support/fake_connectivity.dart';
import '../support/in_memory_secure_store.dart';

class _FakeSchedule extends ScheduleController {
  @override
  DataState<WeekSchedule> build(DateTime monday) => DataSuccess<WeekSchedule>(
        WeekSchedule(monday: monday, courses: const <Course>[]),
        DateTime(2026, 10, 12, 9),
      );

  @override
  Future<void> refresh() async {}
}

class _FakeGrades extends GradesController {
  @override
  DataState<GradesSnapshot> build(String period) => DataSuccess<GradesSnapshot>(
        GradesSnapshot(
          periods: const [SchoolPeriod(value: '30', label: 'SEMESTRE 1')],
          selectedPeriod: '30',
          grades: [Grade(value: 15, coefficient: 1, subject: 'ANGLAIS', date: DateTime(2026, 9, 1))],
        ),
        DateTime(2026, 10, 12, 9),
      );

  @override
  Future<void> refresh() async {}
}

void main() {
  testWidgets('accueil au démarrage, changement d\'onglet, retour Android vers l\'accueil', (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => DateTime(2026, 10, 12, 10)),
          secureKeyValueStoreProvider.overrideWithValue(InMemorySecureKeyValueStore()),
          settingsBoxProvider.overrideWithValue(null),
          connectivityProvider.overrideWithValue(FakeConnectivity()),
          scheduleControllerProvider.overrideWith(_FakeSchedule.new),
          gradesControllerProvider.overrideWith(_FakeGrades.new),
        ],
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pump();

    expect(find.text('Bonjour 👋'), findsOneWidget);
    expect(find.text('MOYENNE GÉNÉRALE'), findsNothing);

    await tester.tap(find.byIcon(Icons.school_outlined));
    await tester.pumpAndSettle();
    expect(find.text('MOYENNE GÉNÉRALE'), findsOneWidget);
    expect(find.text('Bonjour 👋'), findsNothing);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Thème de l\'application'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Emploi du temps'), findsOneWidget);

    // Bouton retour d'Android : d'abord l'accueil.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Bonjour 👋'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
