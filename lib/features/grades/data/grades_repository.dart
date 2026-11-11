import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/session/session_manager.dart';
import 'package:mygalia/core/storage/cache_store.dart';
import 'package:mygalia/features/grades/data/grades_remote_data_source.dart';
import 'package:mygalia/features/grades/domain/grade.dart';

/// Notes : le réseau fait foi, le cache sert à l'affichage immédiat et de
/// secours hors ligne.
class GradesRepository {
  GradesRepository(
    this._remote,
    this._cache,
    this._sessions, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final GradesRemoteDataSource _remote;
  final CacheStore _cache;
  final SessionManager _sessions;
  final DateTime Function() _clock;

  /// Une entrée par classe (cursus) et par semestre : les notes de deux
  /// cursus ne se mélangent jamais. Valeurs vides : ce que l'espace école
  /// affiche par défaut.
  static String _key(String periodValue, String classValue) => [
        'notes',
        if (classValue.isNotEmpty) 'classe-$classValue',
        periodValue.isEmpty ? 'courant' : periodValue,
      ].join(':');

  CachedValue<GradesSnapshot>? cached(String periodValue, {String classValue = ''}) {
    final String key = _key(periodValue, classValue);
    final CachedValue<GradesSnapshot>? cached =
        _cache.read(key, GradesSnapshot.fromJson);
    AppLog.cache(
      '$key : ${cached == null ? 'absent du cache' : 'cache du ${cached.savedAt}'}',
    );
    return cached;
  }

  /// Interroge TOUJOURS le réseau ; n'enregistre que des notes valides.
  Future<CachedValue<GradesSnapshot>> fetch(
    String periodValue, {
    String classValue = '',
    CancelToken? cancelToken,
  }) async {
    final String key = _key(periodValue, classValue);
    AppLog.cache('$key : réseau');
    final int epoch = _sessions.epoch;
    final GradesSnapshot snapshot = await _remote.fetch(
      classValue: classValue,
      periodValue: periodValue,
      cancelToken: cancelToken,
    );
    // Déconnexion pendant le chargement : rien ne doit rester sur le disque.
    if (_sessions.epoch != epoch) throw const CancelledFailure();
    final DateTime savedAt = _clock();
    await _cache.write(key, snapshot.toJson(), savedAt);
    return CachedValue<GradesSnapshot>(snapshot, savedAt);
  }
}

final gradesRepositoryProvider = Provider<GradesRepository>((ref) {
  return GradesRepository(
    ref.watch(gradesRemoteDataSourceProvider),
    ref.watch(cacheStoreProvider),
    ref.watch(sessionManagerProvider),
  );
});
