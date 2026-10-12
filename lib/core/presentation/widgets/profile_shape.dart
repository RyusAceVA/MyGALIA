import 'package:flutter/material.dart';

import 'package:mygalia/core/presentation/expressive/material_shapes.dart';
import 'package:mygalia/core/presentation/expressive/shape_badge.dart';

/// Initiale du compte dans un biscuit à douze bosses (forme Material 3
/// Expressive), née d'un cercle à son apparition. Touchable si [onTap].
class ProfileShape extends StatelessWidget {
  const ProfileShape({
    super.key,
    required this.email,
    this.size = 56,
    this.onTap,
    this.tooltip,
  });

  final String email;
  final double size;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final MaterialShape shape = MaterialShapes.cookie12;
    final Widget badge = ShapeBadge(
      shape: shape,
      initialShape: MaterialShapes.circle,
      size: size,
      color: scheme.primaryContainer,
      child: Text(
        email.isEmpty ? '?' : email[0].toUpperCase(),
        style: theme.textTheme.titleLarge?.copyWith(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final VoidCallback? tap = onTap;
    if (tap == null) return badge;
    final MaterialShapeBorder border = MaterialShapeBorder(shape);
    // Ondulation au-dessus de la forme, découpée à son contour.
    final Widget tappable = Stack(
      children: [
        badge,
        Positioned.fill(
          child: Material(
            type: MaterialType.transparency,
            shape: border,
            clipBehavior: Clip.antiAlias,
            child: InkWell(customBorder: border, onTap: tap),
          ),
        ),
      ],
    );
    final String? message = tooltip;
    return message == null ? tappable : Tooltip(message: message, child: tappable);
  }
}
