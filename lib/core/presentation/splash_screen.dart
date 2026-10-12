import 'package:flutter/material.dart';

import 'package:mygalia/core/constants/app_constants.dart';

/// Écran de garde minimaliste affiché au démarrage.
///
/// Placeholder pour l'étape 1 : il occupe la route d'accueil en attendant
/// le futur routeur (auth guard -> dashboard). Style épuré « Nothing OS » :
/// fond neutre, logotype typographique centré, indicateur discret.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logotype temporaire (sera remplacé par un SVG de marque).
            Text(
              AppConstants.appName,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Une alternative moderne à SC-Form',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
