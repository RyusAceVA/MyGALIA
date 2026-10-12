import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service de stockage **sécurisé** (chiffré au repos).
///
/// Adossé à `flutter_secure_storage` : Keystore côté Android, Keychain côté
/// iOS/macOS. On y range uniquement les données sensibles — pour MyGalia :
///
///  * le **cookie de session SC-Form** (le portail fonctionne par session
///    serveur : après login on récupère un cookie type `JSESSIONID`/`PHPSESSID`
///    à ré-injecter à chaque requête) ;
///  * d'éventuels tokens / identifiants mémorisés.
///
/// Les données non sensibles (préférences, cache d'emploi du temps) vont dans
/// Hive, pas ici : le stockage chiffré est plus lent et n'a pas vocation à
/// contenir de gros volumes.
class SecureStorageService {
  const SecureStorageService(this._storage);

  final FlutterSecureStorage _storage;

  /// Options Android :
  ///  * `encryptedSharedPreferences` : EncryptedSharedPreferences, clé maître
  ///    dans le Keystore Android ;
  ///  * `resetOnError` : si le contenu est indéchiffrable (clé Keystore perdue,
  ///    fichier restauré d'une sauvegarde…), le plugin efface le coffre au lieu
  ///    d'échouer à chaque lecture. L'utilisateur se reconnecte simplement, au
  ///    lieu de rester bloqué jusqu'à « Effacer le stockage ».
  static const AndroidOptions _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: true,
  );

  static const IOSOptions _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  /// Enregistre une valeur textuelle sous [key].
  Future<void> saveString(String key, String value) {
    return _storage.write(
      key: key,
      value: value,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
  }

  /// Lit la valeur associée à [key], ou `null` si absente.
  Future<String?> getString(String key) {
    return _storage.read(
      key: key,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
  }

  /// Indique si une valeur existe pour [key] (utile pour un check de session).
  Future<bool> containsKey(String key) {
    return _storage.containsKey(
      key: key,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
  }

  /// Supprime la valeur associée à [key].
  Future<void> delete(String key) {
    return _storage.delete(
      key: key,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
  }

  /// Purge complète — typiquement appelée lors d'un logout.
  Future<void> clearAll() {
    return _storage.deleteAll(
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
  }
}

/// Provider injectable dans la couche `data/` des features.
///
/// Manuel (pas de codegen `@riverpod`) pour rester compilable sans build_runner.
/// Migration possible vers `@riverpod` ultérieurement sans impact sur les
/// consommateurs qui lisent déjà `secureStorageServiceProvider`.
final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return const SecureStorageService(FlutterSecureStorage());
});
