import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import 'package:mygalia/core/presentation/expressive/material_shapes.dart';

/// Indicateur de chargement Material 3 Expressive : une forme qui se
/// transforme en tournant (éclat, biscuit, pentagone, pilule, soleil…).
///
/// Sans [progress] : animation continue, pour une attente de durée
/// inconnue. Avec [progress] (0 → 1, au-delà la forme continue de
/// tourner) : un cercle devient un éclat en tournant — c'est le geste
/// « tirer pour actualiser ».
///
/// [contained] : forme posée sur un disque coloré (pull-to-refresh, ou
/// par-dessus du contenu).
class ExpressiveLoadingIndicator extends StatefulWidget {
  const ExpressiveLoadingIndicator({
    super.key,
    this.size = 48,
    this.progress,
    this.contained = false,
    this.color,
    this.containerColor,
    this.rotationOffset = 0,
    this.semanticsLabel = 'Chargement en cours',
  });

  /// Côté du conteneur ; la forme en occupe environ les quatre cinquièmes.
  final double size;

  final double? progress;
  final bool contained;

  /// Couleur de la forme (par défaut : primaire, ou « sur conteneur
  /// primaire » si [contained]).
  final Color? color;

  /// Couleur du disque si [contained] (par défaut : conteneur primaire).
  final Color? containerColor;

  /// Angle ajouté (radians) : permet d'enchaîner sans saut la forme
  /// déterminée du geste et l'animation continue.
  final double rotationOffset;

  final String semanticsLabel;

  /// Formes successives de l'animation continue (ordre de Compose).
  static final List<MaterialShape> sequence = [
    MaterialShapes.softBurst,
    MaterialShapes.cookie9,
    MaterialShapes.pentagon,
    MaterialShapes.pill,
    MaterialShapes.sunny,
    MaterialShapes.cookie4,
    MaterialShapes.oval,
  ];

  /// Angle de la forme déterminée à 100 % : l'animation continue démarre
  /// de là avec un [rotationOffset] égal à `rotationAtFull - pi / 2`.
  static const double rotationAtFull = -math.pi;

  @override
  State<ExpressiveLoadingIndicator> createState() => _ExpressiveLoadingIndicatorState();
}

class _ExpressiveLoadingIndicatorState extends State<ExpressiveLoadingIndicator>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<Duration> _clock = ValueNotifier<Duration>(Duration.zero);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    // Créé ici même s'il ne sert pas (progression fixe) : jamais à la
    // destruction du widget, où l'arbre n'est plus consultable.
    _ticker = createTicker((Duration elapsed) => _clock.value = elapsed);
    if (widget.progress == null) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant ExpressiveLoadingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool indeterminate = widget.progress == null;
    if (indeterminate && !_ticker.isActive) {
      _clock.value = Duration.zero;
      _ticker.start();
    } else if (!indeterminate && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double? progress = widget.progress;
    return Semantics(
      label: widget.semanticsLabel,
      value: progress == null ? null : '${(progress.clamp(0, 1) * 100).round()} %',
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _LoadingPainter(
              clock: _clock,
              progress: progress,
              color:
                  widget.color ?? (widget.contained ? scheme.onPrimaryContainer : scheme.primary),
              containerColor:
                  widget.contained ? (widget.containerColor ?? scheme.primaryContainer) : null,
              rotationOffset: widget.rotationOffset,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingPainter extends CustomPainter {
  _LoadingPainter({
    required this.clock,
    required this.progress,
    required this.color,
    required this.containerColor,
    required this.rotationOffset,
  }) : super(repaint: clock);

  /// Une transformation toutes les 650 ms, tour complet en 4,666 s.
  static const double _morphSeconds = 0.65;
  static const double _turnSeconds = 4.666;

  /// Forme active : 38 dp dans un conteneur de 48 dp.
  static const double _activeScale = 38 / 48;

  /// Ressort de chaque transformation (léger dépassement, comme Compose).
  static final SpringSimulation _spring = SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 200, ratio: 0.6),
    0,
    1,
    0,
  );

  /// Plus grand rayon de toutes les formes : en tournant, aucune ne sort
  /// du cercle actif, et la taille ne saute pas d'une forme à l'autre.
  static final double _maxRadius = [
    ...ExpressiveLoadingIndicator.sequence,
    MaterialShapes.circle,
  ].map((MaterialShape s) => s.maxRadius).reduce(math.max);

  final ValueListenable<Duration> clock;
  final double? progress;
  final Color color;
  final Color? containerColor;
  final double rotationOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double side = size.shortestSide;
    final Color? container = containerColor;
    if (container != null) {
      canvas.drawCircle(center, side / 2, Paint()..color = container);
    }
    final double scale = side * _activeScale / (2 * _maxRadius);
    final List<double> radii;
    final double rotation;
    final double? value = progress;
    if (value == null) {
      final List<MaterialShape> shapes = ExpressiveLoadingIndicator.sequence;
      final double seconds = clock.value.inMicroseconds / Duration.microsecondsPerSecond;
      final int step = (seconds / _morphSeconds).floor();
      final double t = _spring.x(seconds - step * _morphSeconds);
      radii = lerpRadii(
        shapes[step % shapes.length].radii,
        shapes[(step + 1) % shapes.length].radii,
        t,
      );
      // Un quart de tour par transformation, plus la rotation lente.
      rotation = rotationOffset +
          (1 + step + t) * math.pi / 2 +
          2 * math.pi * (seconds % _turnSeconds) / _turnSeconds;
    } else {
      final double p = value.clamp(0, 1).toDouble();
      final double beyond = math.max(0, value - 1);
      radii = lerpRadii(MaterialShapes.circle.radii, MaterialShapes.softBurst.radii, p);
      // Sens inverse des aiguilles d'une montre, un demi-tour à 100 %.
      rotation = rotationOffset + ExpressiveLoadingIndicator.rotationAtFull * (p + beyond);
    }
    canvas.drawPath(
      polarPath(radii, center, scale, rotation: rotation),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_LoadingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.containerColor != containerColor ||
      oldDelegate.rotationOffset != rotationOffset ||
      !identical(oldDelegate.clock, clock);
}
