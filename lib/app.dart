import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/constants/app_constants.dart';
import 'package:mygalia/core/presentation/home_shell.dart';
import 'package:mygalia/core/presentation/splash_screen.dart';
import 'package:mygalia/core/settings/theme_mode_controller.dart';
import 'package:mygalia/core/theme/app_theme.dart';
import 'package:mygalia/features/auth/presentation/auth_controller.dart';
import 'package:mygalia/features/auth/presentation/login_screen.dart';

/// Widget racine de MyGalia.
///
/// Configure Material 3 (thèmes clair/sombre, choix mémorisé dans les
/// Paramètres) et aiguille vers l'écran adapté à l'état de connexion.
class MyGaliaApp extends ConsumerWidget {
  const MyGaliaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,

      // Thèmes centralisés dans core/theme.
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),

      // Composants Material en français (sélecteur de date, menus…).
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,

      home: const AuthGate(),
    );
  }
}

/// Écran de garde pendant la lecture du coffre, puis connexion ou accueil.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(authControllerProvider)) {
      AuthRestoring() => const SplashScreen(),
      AuthSignedOut(:final String? message) => LoginScreen(message: message),
      AuthSignedIn() => const HomeShell(),
    };
  }
}
