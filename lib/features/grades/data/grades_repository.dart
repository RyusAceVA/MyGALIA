import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/storage/cache_store.dart';
import 'package:mygalia/features/grades/data/grades_remote_data_source.dart';
import 'package:mygalia/features/grades/domain/grade.dart';

/// Notes : le réseau fait foi, le cache sert à l'affichage immédiat et de
/// secours hors ligne.
class GradesRepository {
  GradesRepository(this._remote, this._cache, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final GradesRemoteDataSource _remote;
  final CacheStore _cache;
  final DateTime Function() _clock;

  /// [periodValue] vide : semestre affiché par défaut par l'espace école.
  static String _key(String periodValue) =>
      'notes:${periodValue.isEmpty ? 'courant' : periodValue}';

  CachedValue<GradesSnapshot>? cached(String periodValue) {
    final CachedValue<GradesSnapshot>? cached =
        _cache.read(_key(periodValue), GradesSnapshot.fromJson);
    AppLog.cache(
      '${_key(periodValue)} : ${cached == null ? 'absent du cache' : 'cache du ${cached.savedAt}'}',
    );
    return cached;
  }

  /// Interroge TOUJOURS le réseau ; n'enregistre que des notes valides.
  Future<CachedValue<GradesSnapshot>> fetch(
    String periodValue, {
    CancelToken? cancelToken,
  }) async {
    AppLog.cache('${_key(periodValue)} : réseau');
    final GradesSnapshot snapshot = await _remote.fetch(
      periodValue: periodValue,
      cancelToken: cancelToken,
    );
    final DateTime savedAt = _clock();
    await _cache.write(_key(periodValue), snapshot.toJson(), savedAt);
    return CachedValue<GradesSnapshot>(snapshot, savedAt);
  }
}

final gradesRepositoryProvider = Provider<GradesRepository>((ref) {
  return GradesRepository(
    ref.watch(gradesRemoteDataSourceProvider),
    ref.watch(cacheStoreProvider),
  );
});
