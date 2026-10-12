import 'package:flutter/material.dart';

import 'package:mygalia/core/constants/app_constants.dart';
import 'package:mygalia/core/presentation/splash_screen.dart';
import 'package:mygalia/core/theme/app_theme.dart';

/// Widget racine de MyGalia.
///
/// Configure Material 3 (thèmes clair/sombre + suivi du mode système) et
/// pointe vers l'écran de garde. Le routeur définitif (auth guard -> shell)
/// remplacera `home` lors d'une étape ultérieure.
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

      home: const SplashScreen(),
    );
  }
}
