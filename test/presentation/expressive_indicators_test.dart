import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/presentation/expressive/expressive_refresh_indicator.dart';
import 'package:mygalia/core/presentation/expressive/loading_indicator.dart';
import 'package:mygalia/core/presentation/expressive/wavy_progress_indicator.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
      home: Builder(
        builder: (BuildContext context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(body: child),
        ),
      ),
    );

/// Liste courte sous l'indicateur de rafraîchissement.
Widget _refreshable({
  required Future<void> Function() onRefresh,
  bool refreshing = false,
}) =>
    _app(
      ExpressiveRefreshIndicator(
        onRefresh: onRefresh,
        refreshing: refreshing,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            for (int i = 0; i < 4; i++) SizedBox(height: 80, child: Text('Ligne $i')),
          ],
        ),
      ),
    );

Finder get _shapes => find.byType(ExpressiveLoadingIndicator);

void main() {
  group('indicateur à formes', () {
    testWidgets('sans progression : animation continue', (tester) async {
      await tester.pumpWidget(_app(const Center(child: ExpressiveLoadingIndicator())));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(find.bySemanticsLabel('Chargement en cours'), findsOneWidget);
    });

    testWidgets('avec progression : immobile, valeur annoncée', (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(const Center(child: ExpressiveLoadingIndicator(progress: 0.4))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(
        tester.getSemantics(_shapes),
        matchesSemantics(label: 'Chargement en cours', value: '40 %'),
      );
      semantics.dispose();
    });

    testWidgets('onglet inactif (TickerMode) : aucune image demandée', (tester) async {
      await tester.pumpWidget(
        _app(const TickerMode(enabled: false, child: Center(child: ExpressiveLoadingIndicator()))),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('progression en vague', () {
    testWidgets('sans valeur : animation continue', (tester) async {
      await tester.pumpWidget(_app(const WavyLinearProgressIndicator()));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(tester.getSize(find.byType(WavyLinearProgressIndicator)).height, 10);
    });

    testWidgets('au milieu : la vague défile ; au début et à la fin : plate et immobile',
        (tester) async {
      await tester.pumpWidget(_app(const WavyLinearProgressIndicator(value: 0.5)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'vague qui défile');

      await tester.pumpWidget(_app(const WavyLinearProgressIndicator(value: 0.97)));
      // La vague s'aplatit en douceur puis plus rien ne bouge.
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.pumpWidget(_app(const WavyLinearProgressIndicator(value: 0.05)));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('animations réduites : vague immobile', (tester) async {
      await tester.pumpWidget(
        _app(const WavyLinearProgressIndicator(value: 0.5), reduceMotion: true),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('valeur annoncée aux lecteurs d\'écran', (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(const WavyLinearProgressIndicator(value: 0.25, semanticsLabel: 'Avancement du cours')),
      );
      expect(
        tester.getSemantics(find.byType(WavyLinearProgressIndicator)),
        matchesSemantics(label: 'Avancement du cours', value: '25 %'),
      );
      semantics.dispose();
    });
  });

  group('tirer pour actualiser', () {
    testWidgets(
        'tiré assez bas : un seul rafraîchissement, formes pendant l\'attente, puis disparition',
        (tester) async {
      final Completer<void> done = Completer<void>();
      int calls = 0;
      await tester.pumpWidget(_refreshable(onRefresh: () {
        calls++;
        return done.future;
      }));
      expect(_shapes, findsNothing);

      await tester.fling(find.text('Ligne 0'), const Offset(0, 300), 1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(calls, 1);
      expect(_shapes, findsOneWidget);
      expect(tester.widget<ExpressiveLoadingIndicator>(_shapes).progress, isNull,
          reason: 'animation continue pendant le rafraîchissement');

      done.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_shapes, findsNothing);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pendant le geste : la forme suit la traction', (tester) async {
      await tester.pumpWidget(_refreshable(onRefresh: () async {}));
      final TestGesture gesture = await tester.startGesture(tester.getCenter(find.text('Ligne 0')));
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      final double? early = tester.widget<ExpressiveLoadingIndicator>(_shapes).progress;
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      final double? later = tester.widget<ExpressiveLoadingIndicator>(_shapes).progress;
      expect(early, isNotNull);
      expect(later, greaterThan(early!));
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('traction trop courte : rien ne se passe', (tester) async {
      int calls = 0;
      await tester.pumpWidget(_refreshable(onRefresh: () async => calls++));
      await tester.drag(find.text('Ligne 0'), const Offset(0, 40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(calls, 0);
      expect(_shapes, findsNothing);
    });

    testWidgets('rafraîchissement lancé ailleurs : l\'indicateur apparaît puis s\'en va',
        (tester) async {
      int calls = 0;
      Future<void> onRefresh() async => calls++;
      await tester.pumpWidget(_refreshable(onRefresh: onRefresh));
      await tester.pumpWidget(_refreshable(onRefresh: onRefresh, refreshing: true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_shapes, findsOneWidget);
      expect(tester.widget<ExpressiveLoadingIndicator>(_shapes).progress, isNull);

      // Tirer pendant ce temps ne relance rien.
      await tester.fling(find.text('Ligne 0'), const Offset(0, 300), 1000);
      await tester.pump(const Duration(milliseconds: 400));
      expect(calls, 0);

      await tester.pumpWidget(_refreshable(onRefresh: onRefresh));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_shapes, findsNothing);
    });

    testWidgets('déjà en cours à l\'ouverture : indicateur affiché', (tester) async {
      await tester.pumpWidget(_refreshable(onRefresh: () async {}, refreshing: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_shapes, findsOneWidget);
    });
  });
}
