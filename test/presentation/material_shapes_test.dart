import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/presentation/expressive/material_shapes.dart';
import 'package:mygalia/core/presentation/expressive/shape_badge.dart';

void main() {
  group('catalogue', () {
    test('chaque forme remplit le carré unité sur son plus grand côté, centrée', () {
      for (final MaterialShape shape in MaterialShapes.all) {
        final Rect bounds = _tightBounds(shape.toPath(const Rect.fromLTWH(0, 0, 1, 1)));
        final double side = math.max(bounds.width, bounds.height);
        expect(side, closeTo(1, 0.02), reason: shape.name);
        expect(bounds.center.dx, closeTo(0.5, 0.02), reason: shape.name);
        expect(bounds.center.dy, closeTo(0.5, 0.02), reason: shape.name);
      }
    });

    test('le cercle est un cercle', () {
      final List<double> radii = MaterialShapes.circle.radii;
      expect(radii, hasLength(MaterialShape.samples));
      for (final double r in radii) {
        expect(r, closeTo(0.5, 0.005));
      }
    });

    test('contour polaire fermé : aucune direction sans bord, rien hors du carré', () {
      for (final MaterialShape shape in MaterialShapes.all) {
        for (final double r in shape.radii) {
          expect(r, greaterThan(0.1), reason: shape.name);
          expect(r, lessThanOrEqualTo(math.sqrt2 / 2 + 1e-6), reason: shape.name);
        }
      }
    });

    test('les biscuits alternent bosses et creux, le carré a ses coins sur les diagonales', () {
      final List<double> cookie = MaterialShapes.cookie9.radii;
      final double spread = cookie.reduce(math.max) - cookie.reduce(math.min);
      expect(spread, greaterThan(0.03));

      final List<double> square = MaterialShapes.square.radii;
      // Direction 0 = axe des x ; 45° = 1/8 du tour.
      expect(square[MaterialShape.samples ~/ 8], greaterThan(square[0]));
    });
  });

  group('morphing', () {
    test('interpolation : extrémités exactes, rebond sans rayon négatif', () {
      final List<double> a = MaterialShapes.circle.radii;
      final List<double> b = MaterialShapes.sunny.radii;
      expect(lerpRadii(a, b, 0), a);
      expect(lerpRadii(a, b, 1), b);
      final List<double> overshoot = lerpRadii(a, b, 1.2);
      expect(overshoot.every((double r) => r >= 0), isTrue);
      expect(lerpRadii(a, b, -50).every((double r) => r >= 0), isTrue);
    });

    test('contour polaire mis à l\'échelle et centré', () {
      final Path path = polarPath(MaterialShapes.circle.radii, const Offset(50, 40), 20);
      final Rect bounds = path.getBounds();
      expect(bounds.center.dx, closeTo(50, 0.2));
      expect(bounds.center.dy, closeTo(40, 0.2));
      expect(bounds.width, closeTo(20, 0.3));
    });
  });

  test('bordure Material : le contour suit la forme dans le rectangle', () {
    final MaterialShapeBorder border = MaterialShapeBorder(MaterialShapes.flower);
    final Rect bounds = border.getOuterPath(const Rect.fromLTWH(10, 10, 60, 60)).getBounds();
    expect(bounds.left, greaterThanOrEqualTo(9.5));
    expect(bounds.right, lessThanOrEqualTo(70.5));
    expect(border, MaterialShapeBorder(MaterialShapes.flower));
    expect(border == MaterialShapeBorder(MaterialShapes.sunny), isFalse);
  });

  group('ShapeBadge', () {
    Widget badge(MaterialShape shape, {MaterialShape? initial, bool reduceMotion = false}) =>
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
              child: Center(
                child: ShapeBadge(
                  shape: shape,
                  initialShape: initial,
                  color: Colors.indigo,
                  child: const Text('7'),
                ),
              ),
            ),
          ),
        );

    testWidgets('affiche son contenu ; changer de forme anime puis s\'arrête', (tester) async {
      await tester.pumpWidget(badge(MaterialShapes.cookie9));
      expect(find.text('7'), findsOneWidget);

      await tester.pumpWidget(badge(MaterialShapes.sunny));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'transformation en cours');
      // Animation finie : pumpAndSettle se termine.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('apparition : naît de la forme initiale', (tester) async {
      await tester.pumpWidget(badge(MaterialShapes.cookie12, initial: MaterialShapes.circle));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('animations réduites : changement immédiat', (tester) async {
      await tester.pumpWidget(badge(MaterialShapes.cookie9, reduceMotion: true));
      await tester.pumpWidget(badge(MaterialShapes.sunny, reduceMotion: true));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}

/// Rectangle englobant au plus près (getBounds inclut les points de
/// contrôle des courbes).
Rect _tightBounds(Path path) {
  double left = double.infinity;
  double top = double.infinity;
  double right = double.negativeInfinity;
  double bottom = double.negativeInfinity;
  for (final PathMetric metric in path.computeMetrics()) {
    for (double d = 0; d <= metric.length; d += metric.length / 2000) {
      final Offset p = metric.getTangentForOffset(d)!.position;
      left = math.min(left, p.dx);
      top = math.min(top, p.dy);
      right = math.max(right, p.dx);
      bottom = math.max(bottom, p.dy);
    }
  }
  return Rect.fromLTRB(left, top, right, bottom);
}
