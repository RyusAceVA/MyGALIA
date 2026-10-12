import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'package:mygalia/core/constants/app_constants.dart';
import 'package:mygalia/core/debug/app_log.dart';

/// Valeur relue du cache, avec sa date d'enregistrement.
@immutable
class CachedValue<T> {
  const CachedValue(this.data, this.savedAt);

  final T data;
  final DateTime savedAt;
}

/// Cache local (Hive) des dernières données VALIDES.
///
///  * On n'y écrit qu'après un parsing réussi et validé : jamais une page
///    d'erreur, vide ou de connexion. Les repositories n'appellent [write]
///    qu'avec des données saines.
///  * Il sert à l'affichage immédiat et de secours hors ligne, jamais à la
///    place du réseau lors d'un rafraîchissement.
///  * Une entrée illisible (JSON corrompu, structure inattendue, ancienne
///    version de format) est supprimée et traitée comme absente.
class CacheStore {
  CacheStore(this._box);

  final Box<dynamic> _box;

  /// Version du format des entrées : à incrémenter si leur structure change.
  static const int schemaVersion = 1;

  CachedValue<T>? read<T>(
    String key,
    T Function(Map<String, Object?> json) decode,
  ) {
    final Object? raw = _box.get(key);
    if (raw == null) return null;
    try {
      if (raw is! String) throw const FormatException('entrée non textuelle');
      final Map<String, Object?> entry =
          (jsonDecode(raw) as Map<Object?, Object?>).cast<String, Object?>();
      if (entry['v'] != schemaVersion) {
        throw const FormatException('version de format différente');
      }
      final DateTime savedAt = DateTime.parse(entry['savedAt']! as String);
      final T data = decode(
        (entry['data']! as Map<Object?, Object?>).cast<String, Object?>(),
      );
      return CachedValue<T>(data, savedAt);
    } on Object catch (e) {
      AppLog.cache('$key : entrée illisible (${e.runtimeType}), supprimée');
      unawaited(_delete(key));
      return null;
    }
  }

  Future<void> write(
    String key,
    Map<String, Object?> data,
    DateTime savedAt,
  ) async {
    try {
      await _box.put(
        key,
        jsonEncode({
          'v': schemaVersion,
          'savedAt': savedAt.toIso8601String(),
          'data': data,
        }),
      );
      AppLog.cache('$key : données valides enregistrées');
    } on Object catch (e) {
      // Un cache non écrit ne doit jamais faire échouer un chargement réussi.
      AppLog.error('cache : écriture de $key impossible (${e.runtimeType})');
    }
  }

  Future<void> clear() async {
    try {
      await _box.clear();
      AppLog.cache('cache vidé');
    } on Object catch (e) {
      AppLog.error('cache : purge impossible (${e.runtimeType})');
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _box.delete(key);
    } on Object {
      // Au pire, l'entrée sera de nouveau ignorée à la prochaine lecture.
    }
  }
}

/// Cache applicatif (boîte ouverte dans `main`, surchargée en test).
final cacheStoreProvider = Provider<CacheStore>((ref) {
  return CacheStore(Hive.box<dynamic>(AppConstants.cacheBox));
});
