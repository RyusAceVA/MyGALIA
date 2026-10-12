import 'package:flutter/material.dart';

/// Palette centrale de MyGalia.
///
/// Direction artistique : minimalisme « Nothing OS / Pixel » —
/// une base de neutres très sobres (presque noir / blanc cassé) rehaussée
/// par un accent indigo/violet utilisé avec parcimonie.
///
/// On expose deux [ColorScheme] générés via [ColorScheme.fromSeed] (Material 3),
/// puis on affine quelques tons de surface pour obtenir des fonds « encre »
/// en mode sombre, plus proches de l'esthétique voulue que le rendu par défaut.
abstract final class AppColors {
  AppColors._();

  /// Couleur graine : indigo moderne. Toute l'harmonie M3 en découle.
  static const Color seed = Color(0xFF6366F1);

  /// Accent secondaire discret (violet) pour les états sélectionnés.
  static const Color accent = Color(0xFF8B5CF6);

  // --- Neutres « encre » (mode sombre, style Nothing OS) -------------------
  static const Color inkBackground = Color(0xFF0A0A0B); // fond quasi noir
  static const Color inkSurface = Color(0xFF141416); // cartes / feuilles
  static const Color inkSurfaceHigh = Color(0xFF1D1D21); // éléments surélevés

  // --- Neutres clairs ------------------------------------------------------
  static const Color paperBackground = Color(0xFFFBFBFD); // blanc cassé
  static const Color paperSurface = Color(0xFFFFFFFF);

  /// Rouge d'erreur cohérent entre les deux thèmes.
  static const Color danger = Color(0xFFE5484D);

  // -------------------------------------------------------------------------
  // ColorSchemes
  // -------------------------------------------------------------------------

  /// Schéma clair : neutres papier + accent indigo.
  static ColorScheme get light => ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.light,
        error: danger,
      ).copyWith(
        surface: paperSurface,
        surfaceContainerLowest: paperBackground,
      );

  /// Schéma sombre : fonds « encre » pour un rendu plus profond que le défaut.
  static ColorScheme get dark => ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
        error: danger,
      ).copyWith(
        surface: inkSurface,
        surfaceContainerLowest: inkBackground,
        surfaceContainerHighest: inkSurfaceHigh,
      );
}
