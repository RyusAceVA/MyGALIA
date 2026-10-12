import 'dart:typed_data';
import 'dart:ui' show lerpDouble;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'package:mygalia/core/presentation/expressive/material_shapes.dart';

/// Forme Material 3 Expressive remplie, contenu centré (icône, chiffre…).
///
/// Changer de [shape], de couleur ou d'angle transforme la forme affichée
/// en la nouvelle, avec un léger rebond (ressort). Avec [initialShape], la
/// forme naît de celle-ci à sa première apparition. Le contenu ne tourne
/// pas avec la forme.
class ShapeBadge extends StatefulWidget {
  const ShapeBadge({
    super.key,
    required this.shape,
    required this.color,
    this.size = 48,
    this.rotation = 0,
    this.initialShape,
    this.child,
  });

  final MaterialShape shape;
  final Color color;
  final double size;

  /// Angle de la forme, en radians.
  final double rotation;

  /// Forme de départ de l'animation d'apparition (aucune si nulle).
  final MaterialShape? initialShape;

  final Widget? child;

  @override
  State<ShapeBadge> createState() => _ShapeBadgeState();
}

class _ShapeBadgeState extends State<ShapeBadge> with SingleTickerProviderStateMixin {
  /// Ressort « spatial » expressif : rapide, avec un petit dépassement.
  static final SpringDescription _spring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 380, ratio: 0.62);

  late final AnimationController _morph = AnimationController.unbounded(vsync: this, value: 1);

  // État de départ de la transformation en cours.
  late List<double> _fromRadii = (widget.initialShape ?? widget.shape).radii;
  late Color _fromColor = widget.color;
  late double _fromRotation = widget.rotation;
  late bool _entrancePending = widget.initialShape != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ici et non dans initState : l'animation consulte MediaQuery.
    if (_entrancePending) {
      _entrancePending = false;
      _animate();
    }
  }

  @override
  void didUpdateWidget(covariant ShapeBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.shape, widget.shape) &&
        oldWidget.color == widget.color &&
        oldWidget.rotation == widget.rotation) {
      return;
    }
    // Repart de ce qui est affiché à cet instant (transformation
    // éventuellement interrompue).
    final double t = _morph.value;
    _fromRadii = lerpRadii(_fromRadii, oldWidget.shape.radii, t);
    _fromColor = Color.lerp(_fromColor, oldWidget.color, t.clamp(0, 1))!;
    _fromRotation = lerpDouble(_fromRotation, oldWidget.rotation, t)!;
    _animate();
  }

  void _animate() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _morph.value = 1;
      return;
    }
    _morph
      ..value = 0
      ..animateWith(SpringSimulation(_spring, 0, 1, 0));
  }

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _ShapePainter(
          morph: _morph,
          fromRadii: _fromRadii,
          toRadii: widget.shape.radii,
          fromColor: _fromColor,
          toColor: widget.color,
          fromRotation: _fromRotation,
          toRotation: widget.rotation,
        ),
        child: Center(child: widget.child),
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  _ShapePainter({
    required this.morph,
    required this.fromRadii,
    required this.toRadii,
    required this.fromColor,
    required this.toColor,
    required this.fromRotation,
    required this.toRotation,
  }) : super(repaint: morph);

  final Animation<double> morph;
  final List<double> fromRadii;
  final Float64List toRadii;
  final Color fromColor;
  final Color toColor;
  final double fromRotation;
  final double toRotation;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = morph.value;
    final List<double> radii = t == 1 ? toRadii : lerpRadii(fromRadii, toRadii, t);
    canvas.drawPath(
      polarPath(
        radii,
        size.center(Offset.zero),
        size.shortestSide,
        rotation: lerpDouble(fromRotation, toRotation, t)!,
      ),
      Paint()..color = Color.lerp(fromColor, toColor, t.clamp(0, 1))!,
    );
  }

  @override
  bool shouldRepaint(_ShapePainter oldDelegate) =>
      !identical(oldDelegate.fromRadii, fromRadii) ||
      !identical(oldDelegate.toRadii, toRadii) ||
      oldDelegate.fromColor != fromColor ||
      oldDelegate.toColor != toColor ||
      oldDelegate.fromRotation != fromRotation ||
      oldDelegate.toRotation != toRotation;
}
