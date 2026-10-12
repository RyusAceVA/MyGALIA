import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/constants/app_constants.dart';
import 'package:mygalia/core/presentation/home_shell.dart';
import 'package:mygalia/core/presentation/splash_screen.dart';
import 'package:mygalia/core/theme/app_theme.dart';
import 'package:mygalia/features/auth/presentation/auth_controller.dart';
import 'package:mygalia/features/auth/presentation/login_screen.dart';

/// Widget racine de MyGalia.
///
/// Configure Material 3 (thèmes clair/sombre + suivi du mode système) et
/// aiguille vers l'écran adapté à l'état de connexion.
class MyGaliaApp extends StatelessWidget {
  const MyGaliaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,

      // Thèmes centralisés dans core/theme.
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system, // suit le réglage de l'OS pour l'instant

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
