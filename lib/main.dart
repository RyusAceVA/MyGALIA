import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:mygalia/app.dart';
import 'package:mygalia/core/constants/app_constants.dart';
import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/storage/cache_box.dart';
import 'package:mygalia/core/storage/secure_storage_service.dart';

/// Point d'entrée de MyGalia.
///
/// Ordre d'initialisation :
///   1. Binding Flutter (obligatoire avant tout appel asynchrone au démarrage).
///   2. Hive : préférences, puis cache local chiffré.
///   3. Montage de l'arbre sous [ProviderScope] — racine de Riverpod : tous les
///      providers de l'app y vivent.
Future<void> main() async {
  // Nécessaire car on effectue des appels async (Hive) avant runApp().
  WidgetsFlutterBinding.ensureInitialized();

  // --- Stockage local (Hive) ---------------------------------------------
  await Hive.initFlutter();
  await _openBox(AppConstants.settingsBox);
  // Planning et notes : boîte chiffrée, clé dans le coffre.
  await deleteLegacyCache();
  await openEncryptedBox(
    AppConstants.cacheBox,
    SecureStorageService(const FlutterSecureKeyValueStore()),
  );

  // ProviderScope : conteneur racine de Riverpod. Indispensable pour que
  // n'importe quel widget descendant puisse lire/observer des providers.
  runApp(
    const ProviderScope(
      child: MyGaliaApp(),
    ),
  );
}

/// Ouvre une boîte Hive. Si son fichier est illisible, elle est recréée vide
/// plutôt que de bloquer le démarrage : le cache se reconstruit depuis le
/// serveur, alors qu'une exception ici laisserait l'app figée au lancement.
Future<void> _openBox(String name) async {
  try {
    await Hive.openBox<dynamic>(name);
  } on Object catch (e) {
    AppLog.error('Hive : boîte « $name » illisible (${e.runtimeType}), recréée');
    await Hive.deleteBoxFromDisk(name);
    await Hive.openBox<dynamic>(name);
  }
}
