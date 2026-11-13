import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/constants/app_constants.dart';
import 'package:mygalia/core/presentation/home_shell.dart';
import 'package:mygalia/core/presentation/splash_screen.dart';
import 'package:mygalia/core/settings/theme_mode_controller.dart';
import 'package:mygalia/core/theme/app_theme.dart';
import 'package:mygalia/core/theme/system_accent.dart';
import 'package:mygalia/features/auth/presentation/auth_controller.dart';
import 'package:mygalia/features/auth/presentation/login_screen.dart';

/// Widget racine de MyGalia.
///
/// Configure Material 3 (thèmes clair/sombre, choix mémorisé dans les
/// Paramètres, couleurs tirées du fond d'écran sur Android 12+) et aiguille
/// vers l'écran adapté à l'état de connexion.
class MyGaliaApp extends ConsumerStatefulWidget {
  const MyGaliaApp({super.key});

  @override
  ConsumerState<MyGaliaApp> createState() => _MyGaliaAppState();
}

class _MyGaliaAppState extends ConsumerState<MyGaliaApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Le fond d'écran a pu changer pendant que l'app était en arrière-plan.
    if (state == AppLifecycleState.resumed) {
      ref.read(systemAccentProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color? accent = ref.watch(systemAccentProvider);
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,

      // Thèmes centralisés dans core/theme.
      theme: AppTheme.light(accent),
      darkTheme: AppTheme.dark(accent),
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
