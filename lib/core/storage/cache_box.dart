import 'dart:math';

import 'package:hive_flutter/hive_flutter.dart';

import 'package:mygalia/core/constants/app_constants.dart';
import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/storage/secure_storage_service.dart';

/// Ouvre la boîte Hive [name] chiffrée en AES-256 ; la clé vit dans le coffre
/// (Keystore Android).
///
///  * Boîte illisible (clé perdue, fichier abîmé) : recréée vide, le cache se
///    reconstruit depuis le serveur.
///  * Coffre indisponible : clé éphémère et boîte vidée, donc rien de lisible
///    ne reste sur le disque après la fermeture de l'app.
Future<Box<dynamic>> openEncryptedBox(
  String name,
  SecureStorageService vault,
) async {
  List<int>? key = await vault.cacheKey();
  final bool ephemeral = key == null;
  if (key == null) {
    final Random random = Random.secure();
    key = List<int>.generate(32, (_) => random.nextInt(256));
  }
  final HiveAesCipher cipher = HiveAesCipher(key);
  if (ephemeral) await _deleteQuietly(name);
  try {
    return await Hive.openBox<dynamic>(name, encryptionCipher: cipher);
  } on Object catch (e) {
    AppLog.error('Hive : boîte « $name » illisible (${e.runtimeType}), recréée');
    await _deleteQuietly(name);
    return Hive.openBox<dynamic>(name, encryptionCipher: cipher);
  }
}

/// Supprime l'ancienne boîte de cache, écrite en clair.
Future<void> deleteLegacyCache() => _deleteQuietly(AppConstants.legacyCacheBox);

Future<void> _deleteQuietly(String name) async {
  try {
    await Hive.deleteBoxFromDisk(name);
  } on Object catch (e) {
    AppLog.error('Hive : suppression de « $name » impossible (${e.runtimeType})');
  }
}
