import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:mygalia/app.dart';
import 'package:mygalia/core/constants/app_constants.dart';

/// Point d'entrée de MyGalia.
///
/// Ordre d'initialisation :
///   1. Binding Flutter (obligatoire avant tout appel asynchrone au démarrage).  
///   2. Hive (cache local) + ouverture des boîtes de base.
///   3. Montage de l'arbre sous [ProviderScope] — racine de Riverpod : tous les
///      providers de l'app y vivent.
Future<void> main() async {
  // Nécessaire car on effectue des appels async (Hive) avant runApp().
  WidgetsFlutterBinding.ensureInitialized();

  // --- Stockage local (Hive) ---------------------------------------------
  await Hive.initFlutter();
  await Hive.openBox<dynamic>(AppConstants.settingsBox);
  await Hive.openBox<dynamic>(AppConstants.cacheBox);

  // ProviderScope : conteneur racine de Riverpod. Indispensable pour que
  // n'importe quel widget descendant puisse lire/observer des providers.
  runApp(
    const ProviderScope(
      child: MyGaliaApp(),
    ),
  );
}
