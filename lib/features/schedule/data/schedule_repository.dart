import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/storage/cache_store.dart';
import 'package:mygalia/features/schedule/data/schedule_remote_data_source.dart';
import 'package:mygalia/features/schedule/domain/course.dart';

/// Planning : le réseau fait foi, le cache sert à l'affichage immédiat et de
/// secours hors ligne.
class ScheduleRepository {
  ScheduleRepository(this._remote, this._cache, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final ScheduleRemoteDataSource _remote;
  final CacheStore _cache;
  final DateTime Function() _clock;

  static String _key(DateTime monday) =>
      'planning:${monday.year}-${monday.month}-${monday.day}';

  /// Dernière version valide de la semaine, ou `null`.
  CachedValue<WeekSchedule>? cachedWeek(DateTime monday) {
    final CachedValue<WeekSchedule>? cached =
        _cache.read(_key(monday), WeekSchedule.fromJson);
    AppLog.cache(
      '${_key(monday)} : ${cached == null ? 'absent du cache' : 'cache du ${cached.savedAt}'}',
    );
    return cached;
  }

  /// Interroge TOUJOURS le réseau. Seule une semaine complète et valide est
  /// enregistrée : toute erreur (session, réseau, page illisible) laisse le
  /// cache intact.
  Future<CachedValue<WeekSchedule>> fetchWeek(
    DateTime monday, {
    CancelToken? cancelToken,
  }) async {
    AppLog.cache('${_key(monday)} : réseau');
    final WeekSchedule week =
        await _remote.fetchWeek(monday, cancelToken: cancelToken);
    final DateTime savedAt = _clock();
    await _cache.write(_key(monday), week.toJson(), savedAt);
    return CachedValue<WeekSchedule>(week, savedAt);
  }
}

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  return ScheduleRepository(
    ref.watch(scheduleRemoteDataSourceProvider),
    ref.watch(cacheStoreProvider),
  );
});
