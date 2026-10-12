import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/network/failure.dart';

/// Stockage clé/valeur chiffré. Interface minimale pour pouvoir substituer un
/// stockage en mémoire dans les tests.
abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

/// Implémentation Android/iOS : `flutter_secure_storage`.
class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  const FlutterSecureKeyValueStore([this._storage = const FlutterSecureStorage()]);

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

  @override
  Future<String?> read(String key) => _storage.read(
        key: key,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );

  @override
  Future<void> write(String key, String value) => _storage.write(
        key: key,
        value: value,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );

  @override
  Future<void> delete(String key) => _storage.delete(
        key: key,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );

  @override
  Future<void> deleteAll() => _storage.deleteAll(
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );
}

/// Identifiants SC Form. Ne s'affichent jamais (voir [toString]).
class Credentials {
  const Credentials({required this.email, required this.password});

  final String email;
  final String password;

  @override
  String toString() => 'Credentials(•••)';
}

/// Jeton JWT de l'API globale (§2.1).
class ApiToken {
  const ApiToken(this.value, {this.expiresAt});

  final String value;
  final DateTime? expiresAt;

  /// Utilisable s'il reste au moins [margin] avant son expiration annoncée.
  bool isUsable(DateTime now, {Duration margin = const Duration(minutes: 2)}) =>
      value.isNotEmpty &&
      (expiresAt == null || expiresAt!.isAfter(now.add(margin)));

  @override
  String toString() => 'ApiToken(•••, expire: $expiresAt)';
}

/// Coffre-fort des secrets (Keystore Android) : identifiants, jeton API et
/// session école. Rien de tout cela ne va dans Hive ni dans les journaux.
///
/// Les lectures ne lèvent jamais : un coffre illisible équivaut à un coffre
/// vide (l'utilisateur devra se reconnecter), jamais à un blocage.
class SecureStorageService {
  SecureStorageService(this._store);

  final SecureKeyValueStore _store;

  static const String _kCredentials = 'mygalia.credentials';
  static const String _kApiToken = 'mygalia.api_token';
  static const String _kEdcSession = 'mygalia.edc_session';

  Future<Credentials?> readCredentials() async {
    final Map<String, Object?>? json = await _readJson(_kCredentials);
    final Object? email = json?['email'];
    final Object? password = json?['password'];
    if (email is! String || password is! String || email.isEmpty) return null;
    return Credentials(email: email, password: password);
  }

  Future<void> saveCredentials(Credentials credentials) => _writeJson(
        _kCredentials,
        {'email': credentials.email, 'password': credentials.password},
      );

  Future<ApiToken?> readApiToken() async {
    final Map<String, Object?>? json = await _readJson(_kApiToken);
    final Object? value = json?['value'];
    final Object? expires = json?['expiresAt'];
    if (value is! String || value.isEmpty) return null;
    return ApiToken(
      value,
      expiresAt: expires is String ? DateTime.tryParse(expires) : null,
    );
  }

  Future<void> saveApiToken(ApiToken token) => _writeJson(_kApiToken, {
        'value': token.value,
        'expiresAt': token.expiresAt?.toUtc().toIso8601String(),
      });

  Future<void> deleteApiToken() => _delete(_kApiToken);

  /// Session école sérialisée (cookies, segment, pkEntite) : voir `EdcSession`.
  Future<Map<String, Object?>?> readEdcSession() => _readJson(_kEdcSession);

  Future<void> saveEdcSession(Map<String, Object?> json) =>
      _writeJson(_kEdcSession, json);

  Future<void> deleteEdcSession() => _delete(_kEdcSession);

  /// Purge complète (déconnexion, identifiants refusés).
  Future<void> clearAll() async {
    try {
      await _store.deleteAll();
    } on Object catch (e) {
      // Repli : suppression clé par clé.
      AppLog.error('coffre : purge globale impossible (${e.runtimeType})');
      await _delete(_kCredentials);
      await _delete(_kApiToken);
      await _delete(_kEdcSession);
    }
  }

  Future<Map<String, Object?>?> _readJson(String key) async {
    final String? raw;
    try {
      raw = await _store.read(key);
    } on Object catch (e) {
      AppLog.error('coffre : lecture de « $key » impossible (${e.runtimeType})');
      return null;
    }
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, Object?>();
    } on FormatException {
      // Contenu corrompu : traité comme absent, puis supprimé ci-dessous.
    }
    AppLog.error('coffre : « $key » illisible, supprimé');
    await _delete(key);
    return null;
  }

  Future<void> _writeJson(String key, Map<String, Object?> json) async {
    try {
      await _store.write(key, jsonEncode(json));
    } on Object catch (e) {
      throw CacheFailure(
        'Impossible d\'enregistrer les données de connexion sur cet appareil.',
        cause: e,
      );
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _store.delete(key);
    } on Object catch (e) {
      AppLog.error('coffre : suppression de « $key » impossible (${e.runtimeType})');
    }
  }
}

/// Stockage chiffré brut (surchargé par un stockage en mémoire en test).
final secureKeyValueStoreProvider = Provider<SecureKeyValueStore>((ref) {
  return const FlutterSecureKeyValueStore();
});

/// Coffre-fort typé, injecté dans les couches `data/` et `session/`.
final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService(ref.watch(secureKeyValueStoreProvider));
});
