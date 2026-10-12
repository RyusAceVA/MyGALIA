import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Formes Material 3 Expressive (la bibliothèque de formes d'Android 16).
///
/// Flutter ne les fournit pas. Ce fichier porte en Dart la construction des
/// polygones à coins arrondis et lissés d'androidx.graphics.shapes
/// (RoundedPolygon) et les définitions du catalogue MaterialShapes de
/// Compose Material 3. Chaque forme est normalisée dans le carré unité.
///
/// Transformation d'une forme en une autre (morphing) : le contour est
/// échantillonné en coordonnées polaires autour du centre. Ces formes sont
/// toutes étoilées par rapport à leur centre : interpoler les rayons,
/// direction par direction, donne une transition continue et sans
/// croisement.

/// Arrondi d'un sommet : rayon, et lissage (0 = arc de cercle, 1 = courbe
/// adoucie qui s'étend sur le double de longueur).
@immutable
class CornerRounding {
  const CornerRounding([this.radius = 0, this.smoothing = 0]);

  final double radius;
  final double smoothing;

  static const CornerRounding unrounded = CornerRounding();
}

/// Une forme du catalogue, normalisée dans le carré unité (0..1).
class MaterialShape {
  MaterialShape._(this.name, this._cubics);

  /// Directions échantillonnées pour le morphing (une tous les 2°).
  static const int samples = 180;

  final String name;
  final List<_Cubic> _cubics;
  Float64List? _radii;
  double? _maxRadius;

  /// Contour exact, centré dans [rect] (proportions conservées), tourné de
  /// [rotation] radians autour de son centre.
  Path toPath(Rect rect, {double rotation = 0}) {
    final double side = rect.shortestSide;
    final double cos = math.cos(rotation);
    final double sin = math.sin(rotation);
    final Offset center = rect.center;
    Offset map(Offset p) {
      final double x = (p.dx - 0.5) * side;
      final double y = (p.dy - 0.5) * side;
      return center + Offset(x * cos - y * sin, x * sin + y * cos);
    }

    final Offset start = map(_cubics.first.a0);
    final Path path = Path()..moveTo(start.dx, start.dy);
    for (final _Cubic c in _cubics) {
      if (c.isPoint) continue;
      final Offset c0 = map(c.c0);
      final Offset c1 = map(c.c1);
      final Offset a1 = map(c.a1);
      path.cubicTo(c0.dx, c0.dy, c1.dx, c1.dy, a1.dx, a1.dy);
    }
    return path..close();
  }

  /// Rayon du contour (unités du carré unité) dans [samples] directions
  /// régulières autour de (0.5, 0.5), à partir de l'axe des x.
  Float64List get radii => _radii ??= _polarRadii(_cubics, samples);

  /// Distance du centre au point le plus éloigné du contour.
  double get maxRadius => _maxRadius ??= radii.reduce(math.max);

  @override
  String toString() => 'MaterialShape($name)';
}

/// Catalogue (définitions de Compose Material 3, MaterialShapes).
abstract final class MaterialShapes {
  MaterialShapes._();

  static final MaterialShape circle = _shape('circle', _circle(10));
  static final MaterialShape square = _shape('square', _rectangle(1, 1, rounding: _r30));
  static final MaterialShape slanted = _shape(
    'slanted',
    _custom(const [
      _Pnr(Offset(0.926, 0.970), CornerRounding(0.189, 0.811)),
      _Pnr(Offset(-0.021, 0.967), CornerRounding(0.187, 0.057)),
    ], reps: 2),
  );
  static final MaterialShape arch = _shape(
    'arch',
    _rotate(_regular(4, perVertex: const [_r100, _r100, _r20, _r20]), -135),
  );
  static final MaterialShape semiCircle = _shape(
    'semiCircle',
    _rectangle(1.6, 1, perVertex: const [_r20, _r20, _r100, _r100]),
  );
  static final MaterialShape oval = _shape(
    'oval',
    _rotate(_map(_circle(8), (Offset p) => Offset(p.dx, p.dy * 0.64)), -45),
  );
  static final MaterialShape pill = _shape(
    'pill',
    _custom(const [
      _Pnr(Offset(0.961, 0.039), CornerRounding(0.426)),
      _Pnr(Offset(1.001, 0.428)),
      _Pnr(Offset(1.000, 0.609), CornerRounding(1)),
    ], reps: 2, mirroring: true),
  );
  static final MaterialShape triangle =
      _shape('triangle', _rotate(_regular(3, rounding: _r20), -90));
  static final MaterialShape diamond = _shape(
    'diamond',
    _custom(const [
      _Pnr(Offset(0.500, 1.096), CornerRounding(0.151, 0.524)),
      _Pnr(Offset(0.040, 0.500), CornerRounding(0.159)),
    ], reps: 2),
  );
  static final MaterialShape pentagon = _shape(
    'pentagon',
    _custom(const [
      _Pnr(Offset(0.500, -0.009), CornerRounding(0.172)),
      _Pnr(Offset(1.030, 0.365), CornerRounding(0.164)),
      _Pnr(Offset(0.828, 0.970), CornerRounding(0.169)),
    ], reps: 1, mirroring: true),
  );
  static final MaterialShape gem = _shape(
    'gem',
    _custom(const [
      _Pnr(Offset(0.499, 1.023), CornerRounding(0.241, 0.778)),
      _Pnr(Offset(-0.005, 0.792), CornerRounding(0.208)),
      _Pnr(Offset(0.073, 0.258), CornerRounding(0.228)),
      _Pnr(Offset(0.433, -0.000), CornerRounding(0.491)),
    ], reps: 1, mirroring: true),
  );
  static final MaterialShape verySunny = _shape(
    'verySunny',
    _custom(const [
      _Pnr(Offset(0.500, 1.080), CornerRounding(0.085)),
      _Pnr(Offset(0.358, 0.843), CornerRounding(0.085)),
    ], reps: 8),
  );
  static final MaterialShape sunny = _shape('sunny', _star(8, innerRadius: 0.8, rounding: _r15));
  static final MaterialShape cookie4 = _shape(
    'cookie4',
    _custom(const [
      _Pnr(Offset(1.237, 1.236), CornerRounding(0.258)),
      _Pnr(Offset(0.500, 0.918), CornerRounding(0.233)),
    ], reps: 4),
  );
  static final MaterialShape cookie6 = _shape(
    'cookie6',
    _custom(const [
      _Pnr(Offset(0.723, 0.884), CornerRounding(0.394)),
      _Pnr(Offset(0.500, 1.099), CornerRounding(0.398)),
    ], reps: 6),
  );
  static final MaterialShape cookie7 = _shape(
    'cookie7',
    _rotate(_star(7, innerRadius: 0.75, rounding: _r50), -90),
  );
  static final MaterialShape cookie9 = _shape(
    'cookie9',
    _rotate(_star(9, innerRadius: 0.8, rounding: _r50), -90),
  );
  static final MaterialShape cookie12 = _shape(
    'cookie12',
    _rotate(_star(12, innerRadius: 0.8, rounding: _r50), -90),
  );
  static final MaterialShape clover4 = _shape(
    'clover4',
    _custom(const [
      _Pnr(Offset(0.500, 0.074)),
      _Pnr(Offset(0.725, -0.099), CornerRounding(0.476)),
    ], reps: 4, mirroring: true),
  );
  static final MaterialShape clover8 = _shape(
    'clover8',
    _custom(const [
      _Pnr(Offset(0.500, 0.036)),
      _Pnr(Offset(0.758, -0.101), CornerRounding(0.209)),
    ], reps: 8),
  );
  static final MaterialShape burst = _shape(
    'burst',
    _custom(const [
      _Pnr(Offset(0.500, -0.006), CornerRounding(0.006)),
      _Pnr(Offset(0.592, 0.158), CornerRounding(0.006)),
    ], reps: 12),
  );
  static final MaterialShape softBurst = _shape(
    'softBurst',
    _custom(const [
      _Pnr(Offset(0.193, 0.277), CornerRounding(0.053)),
      _Pnr(Offset(0.176, 0.055), CornerRounding(0.053)),
    ], reps: 10),
  );
  static final MaterialShape flower = _shape(
    'flower',
    _custom(const [
      _Pnr(Offset(0.370, 0.187)),
      _Pnr(Offset(0.416, 0.049), CornerRounding(0.381)),
      _Pnr(Offset(0.479, 0.000), CornerRounding(0.095)),
    ], reps: 8, mirroring: true),
  );
  static final MaterialShape puffyDiamond = _shape(
    'puffyDiamond',
    _custom(const [
      _Pnr(Offset(0.870, 0.130), CornerRounding(0.146)),
      _Pnr(Offset(0.818, 0.357)),
      _Pnr(Offset(1.000, 0.332), CornerRounding(0.853)),
    ], reps: 4, mirroring: true),
  );

  /// Toutes les formes, pour les tests et l'inspection visuelle.
  static List<MaterialShape> get all => [
        circle, square, slanted, arch, semiCircle, oval, pill, triangle, //
        diamond, pentagon, gem, verySunny, sunny, cookie4, cookie6, //
        cookie7, cookie9, cookie12, clover4, clover8, burst, softBurst, //
        flower, puffyDiamond,
      ];
}

/// Rayons interpolés entre deux formes. [t] peut sortir de 0..1 (rebond
/// d'un ressort) : la forme dépasse alors légèrement sa cible ; un rayon
/// ne devient jamais négatif.
Float64List lerpRadii(List<double> from, List<double> to, double t) {
  final int n = to.length;
  final Float64List out = Float64List(n);
  for (int i = 0; i < n; i++) {
    out[i] = math.max(0, from[i] + (to[i] - from[i]) * t);
  }
  return out;
}

/// Contour lisse passant par les points polaires [radii] (directions
/// régulières), rayons multipliés par [scale], centré sur [center] et
/// tourné de [rotation] radians.
Path polarPath(List<double> radii, Offset center, double scale, {double rotation = 0}) {
  final int n = radii.length;
  final _Trig trig = _Trig.of(n);
  final double cos = math.cos(rotation);
  final double sin = math.sin(rotation);
  final Float64List xs = Float64List(n);
  final Float64List ys = Float64List(n);
  for (int i = 0; i < n; i++) {
    final double r = radii[i] * scale;
    // Rotation de la direction i : (cos(a + rot), sin(a + rot)).
    xs[i] = center.dx + r * (trig.cos[i] * cos - trig.sin[i] * sin);
    ys[i] = center.dy + r * (trig.sin[i] * cos + trig.cos[i] * sin);
  }
  // Spline de Catmull-Rom fermée, convertie en courbes de Bézier.
  final Path path = Path()..moveTo(xs[0], ys[0]);
  for (int i = 0; i < n; i++) {
    final int prev = (i + n - 1) % n;
    final int next = (i + 1) % n;
    final int after = (i + 2) % n;
    path.cubicTo(
      xs[i] + (xs[next] - xs[prev]) / 6,
      ys[i] + (ys[next] - ys[prev]) / 6,
      xs[next] - (xs[after] - xs[i]) / 6,
      ys[next] - (ys[after] - ys[i]) / 6,
      xs[next],
      ys[next],
    );
  }
  return path..close();
}

/// Bordure Material à la forme d'une [MaterialShape] : fond, découpe et
/// ondulation (InkWell) suivent le contour.
class MaterialShapeBorder extends OutlinedBorder {
  const MaterialShapeBorder(this.shape, {super.side});

  final MaterialShape shape;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      shape.toPath(rect.deflate(side.strokeInset));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => shape.toPath(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(shape.toPath(rect.deflate(side.strokeInset / 2)), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => MaterialShapeBorder(shape, side: side.scale(t));

  @override
  OutlinedBorder copyWith({BorderSide? side}) =>
      MaterialShapeBorder(shape, side: side ?? this.side);

  @override
  bool operator ==(Object other) =>
      other is MaterialShapeBorder && identical(other.shape, shape) && other.side == side;

  @override
  int get hashCode => Object.hash(shape, side);
}

// ---------------------------------------------------------------------------
// Construction (port d'androidx.graphics.shapes)
// ---------------------------------------------------------------------------

const double _distanceEpsilon = 1e-4;

const CornerRounding _r15 = CornerRounding(0.15);
const CornerRounding _r20 = CornerRounding(0.2);
const CornerRounding _r30 = CornerRounding(0.3);
const CornerRounding _r50 = CornerRounding(0.5);
const CornerRounding _r100 = CornerRounding(1);

/// Courbe de Bézier cubique : ancres [a0], [a1], contrôles [c0], [c1].
@immutable
class _Cubic {
  const _Cubic(this.a0, this.c0, this.c1, this.a1);

  factory _Cubic.line(Offset from, Offset to) =>
      _Cubic(from, Offset.lerp(from, to, 1 / 3)!, Offset.lerp(from, to, 2 / 3)!, to);

  /// Arc de cercle de centre [center] entre [p0] et [p1] (même rayon).
  factory _Cubic.circularArc(Offset center, Offset p0, Offset p1) {
    final Offset p0d = _direction(p0 - center);
    final Offset p1d = _direction(p1 - center);
    final Offset rotatedP0 = _rotate90(p0d);
    final Offset rotatedP1 = _rotate90(p1d);
    final bool clockwise = _dot(rotatedP0, p1 - center) >= 0;
    final double cosa = _dot(p0d, p1d);
    if (cosa > 0.999) return _Cubic.line(p0, p1);
    final double k = (p0 - center).distance *
        4 /
        3 *
        (math.sqrt(2 * (1 - cosa)) - math.sqrt(1 - cosa * cosa)) /
        (1 - cosa) *
        (clockwise ? 1 : -1);
    return _Cubic(p0, p0 + rotatedP0 * k, p1 - rotatedP1 * k, p1);
  }

  final Offset a0;
  final Offset c0;
  final Offset c1;
  final Offset a1;

  bool get isPoint => a0 == c0 && c0 == c1 && c1 == a1;

  _Cubic reversed() => _Cubic(a1, c1, c0, a0);

  _Cubic map(Offset Function(Offset) f) => _Cubic(f(a0), f(c0), f(c1), f(a1));

  Offset at(double t) {
    final double u = 1 - t;
    return a0 * (u * u * u) + c0 * (3 * t * u * u) + c1 * (3 * t * t * u) + a1 * (t * t * t);
  }
}

/// Sommet arrondi (et lissé) entre les côtés [p0]→[p1] et [p1]→[p2].
class _RoundedCorner {
  factory _RoundedCorner(Offset p0, Offset p1, Offset p2, CornerRounding rounding) {
    final Offset v01 = p0 - p1;
    final Offset v21 = p2 - p1;
    final double d01 = v01.distance;
    final double d21 = v21.distance;
    if (d01 <= 0 || d21 <= 0) {
      return _RoundedCorner._(p0, p1, p2, Offset.zero, Offset.zero, 0, 0, 0);
    }
    final Offset d1 = v01 / d01;
    final Offset d2 = v21 / d21;
    final double cosAngle = _dot(d1, d2);
    final double sinAngle = math.sqrt(math.max(0, 1 - cosAngle * cosAngle));
    // Longueur à couper sur chaque côté pour un arc de ce rayon :
    // tan(A/2) = sinA / (1 + cosA) = rayon / coupe.
    final double expectedRoundCut =
        sinAngle > 1e-3 ? rounding.radius * (cosAngle + 1) / sinAngle : 0;
    return _RoundedCorner._(
      p0,
      p1,
      p2,
      d1,
      d2,
      rounding.radius,
      rounding.smoothing,
      expectedRoundCut,
    );
  }

  _RoundedCorner._(
    this.p0,
    this.p1,
    this.p2,
    this.d1,
    this.d2,
    this.cornerRadius,
    this.smoothing,
    this.expectedRoundCut,
  );

  final Offset p0;
  final Offset p1;
  final Offset p2;
  final Offset d1;
  final Offset d2;
  final double cornerRadius;
  final double smoothing;
  final double expectedRoundCut;

  /// Le lissage allonge la coupe : 0 = coupe de l'arc, 1 = le double.
  double get expectedCut => (1 + smoothing) * expectedRoundCut;

  List<_Cubic> cubics(double allowedCut0, double allowedCut1) {
    // Le rayon dépend du plus petit côté disponible ; la place restante
    // d'un côté sert au lissage.
    final double allowedCut = math.min(allowedCut0, allowedCut1);
    if (expectedRoundCut < _distanceEpsilon ||
        allowedCut < _distanceEpsilon ||
        cornerRadius < _distanceEpsilon) {
      return [_Cubic.line(p1, p1)];
    }
    final double actualRoundCut = math.min(allowedCut, expectedRoundCut);
    final double actualSmoothing0 = _actualSmoothing(allowedCut0);
    final double actualSmoothing1 = _actualSmoothing(allowedCut1);
    final double actualR = cornerRadius * actualRoundCut / expectedRoundCut;
    final double centerDistance = math.sqrt(actualR * actualR + actualRoundCut * actualRoundCut);
    final Offset center = p1 + _direction((d1 + d2) / 2) * centerDistance;
    final Offset circleIntersection0 = p1 + d1 * actualRoundCut;
    final Offset circleIntersection2 = p1 + d2 * actualRoundCut;
    final _Cubic flanking0 = _flankingCurve(
      actualRoundCut,
      actualSmoothing0,
      p1,
      p0,
      circleIntersection0,
      circleIntersection2,
      center,
      actualR,
    );
    final _Cubic flanking2 = _flankingCurve(
      actualRoundCut,
      actualSmoothing1,
      p1,
      p2,
      circleIntersection2,
      circleIntersection0,
      center,
      actualR,
    ).reversed();
    return [
      flanking0,
      _Cubic.circularArc(center, flanking0.a1, flanking2.a0),
      flanking2,
    ];
  }

  double _actualSmoothing(double allowedCut) {
    if (allowedCut > expectedCut) return smoothing;
    if (allowedCut > expectedRoundCut) {
      return smoothing * (allowedCut - expectedRoundCut) / (expectedCut - expectedRoundCut);
    }
    return 0;
  }

  static _Cubic _flankingCurve(
    double actualRoundCut,
    double actualSmoothing,
    Offset corner,
    Offset sideStart,
    Offset circleSegmentIntersection,
    Offset otherCircleSegmentIntersection,
    Offset circleCenter,
    double actualR,
  ) {
    final Offset sideDirection = _direction(sideStart - corner);
    final Offset curveStart = corner + sideDirection * (actualRoundCut * (1 + actualSmoothing));
    // Part de l'arc remplacée par la courbe de lissage, proportionnelle
    // au lissage.
    final Offset p = Offset.lerp(
      circleSegmentIntersection,
      (circleSegmentIntersection + otherCircleSegmentIntersection) / 2,
      actualSmoothing,
    )!;
    final Offset curveEnd = circleCenter + _direction(p - circleCenter) * actualR;
    final Offset circleTangent = _rotate90(curveEnd - circleCenter);
    final Offset anchorEnd = _lineIntersection(sideStart, sideDirection, curveEnd, circleTangent) ??
        circleSegmentIntersection;
    final Offset anchorStart = (curveStart + anchorEnd * 2) / 3;
    return _Cubic(curveStart, anchorStart, anchorEnd, curveEnd);
  }

  static Offset? _lineIntersection(Offset p0, Offset d0, Offset p1, Offset d1) {
    final Offset rotatedD1 = _rotate90(d1);
    final double den = _dot(d0, rotatedD1);
    if (den.abs() < _distanceEpsilon) return null;
    final double num = _dot(p1 - p0, rotatedD1);
    if (den.abs() < _distanceEpsilon * num.abs()) return null;
    return p0 + d0 * (num / den);
  }
}

/// Polygone aux sommets arrondis : coins, puis côtés droits entre eux.
List<_Cubic> _polygon(List<Offset> vertices, List<CornerRounding> rounding) {
  final int n = vertices.length;
  final List<_RoundedCorner> corners = [
    for (int i = 0; i < n; i++)
      _RoundedCorner(vertices[(i + n - 1) % n], vertices[i], vertices[(i + 1) % n], rounding[i]),
  ];
  // Pour chaque côté (sommet i → i+1) : part réalisable de l'arrondi, puis
  // du lissage, si la longueur du côté ne suffit pas aux deux coins.
  final List<(double, double)> cutAdjusts = [
    for (int i = 0; i < n; i++)
      () {
        final _RoundedCorner a = corners[i];
        final _RoundedCorner b = corners[(i + 1) % n];
        final double expectedRoundCut = a.expectedRoundCut + b.expectedRoundCut;
        final double expectedCut = a.expectedCut + b.expectedCut;
        final double sideSize = (vertices[i] - vertices[(i + 1) % n]).distance;
        if (expectedRoundCut > sideSize) return (sideSize / expectedRoundCut, 0.0);
        if (expectedCut > sideSize) {
          return (1.0, (sideSize - expectedRoundCut) / (expectedCut - expectedRoundCut));
        }
        return (1.0, 1.0);
      }(),
  ];
  final List<List<_Cubic>> cornerCubics = [
    for (int i = 0; i < n; i++)
      () {
        final _RoundedCorner corner = corners[i];
        double allowed(int side) {
          final (double roundRatio, double cutRatio) = cutAdjusts[side];
          return corner.expectedRoundCut * roundRatio +
              (corner.expectedCut - corner.expectedRoundCut) * cutRatio;
        }

        return corner.cubics(allowed((i + n - 1) % n), allowed(i));
      }(),
  ];
  return [
    for (int i = 0; i < n; i++) ...[
      ...cornerCubics[i],
      _Cubic.line(cornerCubics[i].last.a1, cornerCubics[(i + 1) % n].first.a0),
    ],
  ];
}

/// Sommet et arrondi d'une forme décrite point par point.
@immutable
class _Pnr {
  const _Pnr(this.o, [this.r = CornerRounding.unrounded]);

  final Offset o;
  final CornerRounding r;
}

/// Répète [points] [reps] fois autour de [center] ; en miroir, chaque
/// section alterne avec son symétrique.
List<_Pnr> _repeat(List<_Pnr> points, int reps, Offset center, bool mirroring) {
  if (!mirroring) {
    final int np = points.length;
    return [
      for (int it = 0; it < np * reps; it++)
        _Pnr(_rotateDegrees(points[it % np].o, (it ~/ np) * 360 / reps, center), points[it % np].r),
    ];
  }
  final List<double> angles = [
    for (final _Pnr p in points) math.atan2(p.o.dy - center.dy, p.o.dx - center.dx) * 180 / math.pi,
  ];
  final List<double> distances = [for (final _Pnr p in points) (p.o - center).distance];
  final int actualReps = reps * 2;
  final double sectionAngle = 360 / actualReps;
  final List<_Pnr> result = [];
  for (int it = 0; it < actualReps; it++) {
    for (int index = 0; index < points.length; index++) {
      final int i = it.isEven ? index : points.length - 1 - index;
      if (i > 0 || it.isEven) {
        final double degrees =
            sectionAngle * it + (it.isEven ? angles[i] : sectionAngle - angles[i] + 2 * angles[0]);
        final double a = degrees * math.pi / 180;
        result.add(_Pnr(center + Offset(math.cos(a), math.sin(a)) * distances[i], points[i].r));
      }
    }
  }
  return result;
}

List<_Cubic> _custom(
  List<_Pnr> points, {
  required int reps,
  Offset center = const Offset(0.5, 0.5),
  bool mirroring = false,
}) {
  final List<_Pnr> all = _repeat(points, reps, center, mirroring);
  return _polygon([for (final _Pnr p in all) p.o], [for (final _Pnr p in all) p.r]);
}

List<_Cubic> _regular(
  int n, {
  double radius = 1,
  CornerRounding rounding = CornerRounding.unrounded,
  List<CornerRounding>? perVertex,
}) =>
    _polygon(
      [for (int i = 0; i < n; i++) _radial(radius, 2 * math.pi * i / n)],
      perVertex ?? List<CornerRounding>.filled(n, rounding),
    );

/// Cercle fait de [n] arcs : polygone régulier circonscrit, coins arrondis
/// au rayon du cercle.
List<_Cubic> _circle(int n) =>
    _regular(n, radius: 1 / math.cos(math.pi / n), rounding: const CornerRounding(1));

List<_Cubic> _rectangle(
  double width,
  double height, {
  CornerRounding rounding = CornerRounding.unrounded,
  List<CornerRounding>? perVertex,
}) {
  final double l = -width / 2;
  final double t = -height / 2;
  final double r = width / 2;
  final double b = height / 2;
  return _polygon(
    [Offset(r, b), Offset(l, b), Offset(l, t), Offset(r, t)],
    perVertex ?? List<CornerRounding>.filled(4, rounding),
  );
}

List<_Cubic> _star(
  int n, {
  double radius = 1,
  double innerRadius = 0.5,
  CornerRounding rounding = CornerRounding.unrounded,
}) =>
    _polygon(
      [
        for (int i = 0; i < n; i++) ...[
          _radial(radius, math.pi / n * 2 * i),
          _radial(innerRadius, math.pi / n * (2 * i + 1)),
        ],
      ],
      List<CornerRounding>.filled(2 * n, rounding),
    );

List<_Cubic> _map(List<_Cubic> cubics, Offset Function(Offset) f) =>
    [for (final _Cubic c in cubics) c.map(f)];

List<_Cubic> _rotate(List<_Cubic> cubics, double degrees) =>
    _map(cubics, (Offset p) => _rotateDegrees(p, degrees, Offset.zero));

/// Met la forme à l'échelle de son plus grand côté et la centre dans le
/// carré unité.
MaterialShape _shape(String name, List<_Cubic> cubics) {
  double left = double.infinity;
  double top = double.infinity;
  double right = double.negativeInfinity;
  double bottom = double.negativeInfinity;
  for (final _Cubic c in cubics) {
    for (int k = 0; k <= 16; k++) {
      final Offset p = c.at(k / 16);
      left = math.min(left, p.dx);
      top = math.min(top, p.dy);
      right = math.max(right, p.dx);
      bottom = math.max(bottom, p.dy);
    }
  }
  final double width = right - left;
  final double height = bottom - top;
  final double side = math.max(width, height);
  final Offset offset = Offset((side - width) / 2 - left, (side - height) / 2 - top);
  return MaterialShape._(name, _map(cubics, (Offset p) => (p + offset) / side));
}

/// Rayons polaires du contour : pour chaque direction, intersection la
/// plus lointaine du rayon issu du centre avec le contour aplati.
Float64List _polarRadii(List<_Cubic> cubics, int count) {
  const int perCubic = 8;
  final List<Offset> points = [
    for (final _Cubic c in cubics)
      if (!c.isPoint)
        for (int k = 0; k < perCubic; k++) c.at(k / perCubic),
  ];
  const Offset center = Offset(0.5, 0.5);
  final _Trig trig = _Trig.of(count);
  final Float64List radii = Float64List(count);
  for (int j = 0; j < count; j++) {
    final double ux = trig.cos[j];
    final double uy = trig.sin[j];
    double best = 0;
    for (int k = 0; k < points.length; k++) {
      final Offset p = points[k];
      final Offset q = points[(k + 1) % points.length];
      final double ex = q.dx - p.dx;
      final double ey = q.dy - p.dy;
      final double denom = ux * ey - uy * ex;
      if (denom.abs() < 1e-12) continue;
      final double wx = p.dx - center.dx;
      final double wy = p.dy - center.dy;
      final double s = (wx * ey - wy * ex) / denom;
      final double t = (wx * uy - wy * ux) / denom;
      if (s > best && t >= -1e-9 && t <= 1 + 1e-9) best = s;
    }
    radii[j] = best;
  }
  return radii;
}

/// Tables cos / sin des directions régulières (partagées).
class _Trig {
  _Trig._(int n)
      : cos = Float64List.fromList([for (int i = 0; i < n; i++) math.cos(2 * math.pi * i / n)]),
        sin = Float64List.fromList([for (int i = 0; i < n; i++) math.sin(2 * math.pi * i / n)]);

  factory _Trig.of(int n) => _cache.putIfAbsent(n, () => _Trig._(n));

  static final Map<int, _Trig> _cache = <int, _Trig>{};

  final Float64List cos;
  final Float64List sin;
}

Offset _radial(double radius, double angle) =>
    Offset(radius * math.cos(angle), radius * math.sin(angle));

Offset _rotateDegrees(Offset p, double degrees, Offset center) {
  final double a = degrees * math.pi / 180;
  final Offset off = p - center;
  return Offset(
        off.dx * math.cos(a) - off.dy * math.sin(a),
        off.dx * math.sin(a) + off.dy * math.cos(a),
      ) +
      center;
}

Offset _direction(Offset v) {
  final double d = v.distance;
  return d == 0 ? Offset.zero : v / d;
}

Offset _rotate90(Offset v) => Offset(-v.dy, v.dx);

double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;
