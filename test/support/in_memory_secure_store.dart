import 'package:mygalia/core/storage/secure_storage_service.dart';

/// Coffre en mémoire pour les tests (aucun canal de plateforme).
class InMemorySecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> values = <String, String>{};

  /// Simule un coffre indéchiffrable : toute opération échoue.
  bool failAll = false;

  void _check() {
    if (failAll) throw StateError('coffre indisponible (simulation)');
  }

  @override
  Future<String?> read(String key) async {
    _check();
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _check();
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _check();
    values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _check();
    values.clear();
  }
}
