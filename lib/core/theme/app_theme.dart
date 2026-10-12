import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:mygalia/core/theme/app_colors.dart';
import 'package:mygalia/core/theme/app_radius.dart';

/// Fabrique des thèmes Material 3 (clair / sombre) de MyGalia.
///
/// Philosophie :
///   * Material 3 « Expressive » — angles très arrondis, surfaces douces,
///     hiérarchie typographique marquée.
///   * Typo : Space Grotesk pour les titres (caractère « tech/Nothing »),
///     Inter pour le corps de texte (lisibilité).
///   * Transitions de page unifiées et fluides sur toutes les plateformes.
///
/// Tout est exposé en statique : aucun état, on ne construit les [ThemeData]
/// qu'une fois au démarrage.
abstract final class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(AppColors.light);
  static ThemeData get dark => _build(AppColors.dark);

  // -------------------------------------------------------------------------
  // Construction commune : on dérive tout le thème du ColorScheme fourni,
  // ce qui garantit que clair et sombre restent parfaitement symétriques.
  // -------------------------------------------------------------------------
  static ThemeData _build(ColorScheme scheme) {
    final bool isDark = scheme.brightness == Brightness.dark;

    // Typographie : on part du textTheme M3 par défaut adapté au brightness,
    // puis on applique les deux familles Google Fonts.
    final TextTheme baseText =
        (isDark ? Typography.material2021().white : Typography.material2021().black);
    final TextTheme textTheme = GoogleFonts.interTextTheme(baseText).copyWith(
      displayLarge: GoogleFonts.spaceGrotesk(textStyle: baseText.displayLarge, fontWeight: FontWeight.w700),
      displayMedium: GoogleFonts.spaceGrotesk(textStyle: baseText.displayMedium, fontWeight: FontWeight.w700),
      displaySmall: GoogleFonts.spaceGrotesk(textStyle: baseText.displaySmall, fontWeight: FontWeight.w600),
      headlineLarge: GoogleFonts.spaceGrotesk(textStyle: baseText.headlineLarge, fontWeight: FontWeight.w600),
      headlineMedium: GoogleFonts.spaceGrotesk(textStyle: baseText.headlineMedium, fontWeight: FontWeight.w600),
      headlineSmall: GoogleFonts.spaceGrotesk(textStyle: baseText.headlineSmall, fontWeight: FontWeight.w600),
      titleLarge: GoogleFonts.spaceGrotesk(textStyle: baseText.titleLarge, fontWeight: FontWeight.w600),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surfaceContainerLowest,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory, // ripple « Expressive »

      // --- Transitions de page fluides et cohérentes multi-plateformes -----
      // ZoomPageTransitionsBuilder = transition M3 (fondu + léger zoom),
      // appliquée partout pour un ressenti homogène.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),

      // --- Barre d'application : épurée, sans ombre -------------------------
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),

      // --- Cartes : angles très arrondis, ombre quasi absente --------------
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      ),

      // --- Champs de saisie : remplis, bordures arrondies 16px -------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.4 : 0.6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        hintStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        // Pas de bordure au repos -> aspect « surface douce ».
        border: const OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: BorderSide.none,
        ),
        // À la sélection, l'accent primaire souligne le champ actif.
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),

      // --- Boutons : hauteur confortable, coins pleinement arrondis --------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.input),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size.fromHeight(56),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.input),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          side: BorderSide(color: scheme.outlineVariant),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.input),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
          ),
        ),
      ),

      // --- Chips : forme « pilule » ---------------------------------------
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.secondaryContainer,
        labelStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),

      // --- Feuilles / dialogs : large arrondi supérieur --------------------
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      ),

      // --- Navigation basse : sobre, sans teinte de surface ---------------
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 72,
        indicatorColor: scheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
        thickness: 1,
      ),
    );
  }
}
