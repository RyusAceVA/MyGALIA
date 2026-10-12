import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/presentation/data_loader.dart';
import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/core/storage/cache_store.dart';
import 'package:mygalia/features/schedule/data/schedule_repository.dart';
import 'package:mygalia/features/schedule/domain/course.dart';

/// Lundi de la semaine affichée (flèches ‹ › et « cette semaine »).
final scheduleWeekProvider = StateProvider.autoDispose<DateTime>((ref) {
  return mondayOf(DateTime.now());
});

/// Un contrôleur par semaine : changer de semaine ne mélange jamais les
/// données, et la semaine quittée annule son éventuelle requête.
final scheduleControllerProvider = NotifierProvider.autoDispose
    .family<ScheduleController, DataState<WeekSchedule>, DateTime>(
  ScheduleController.new,
);

class ScheduleController
    extends AutoDisposeFamilyNotifier<DataState<WeekSchedule>, DateTime>
    with DataLoader<WeekSchedule, DateTime> {
  @override
  DataState<WeekSchedule> build(DateTime monday) => startLoading();

  @override
  String get label => 'planning semaine du ${arg.day}/${arg.month}';

  @override
  CachedValue<WeekSchedule>? readCache() =>
      ref.read(scheduleRepositoryProvider).cachedWeek(arg);

  @override
  Future<CachedValue<WeekSchedule>> fetch(CancelToken cancelToken) =>
      ref.read(scheduleRepositoryProvider).fetchWeek(arg, cancelToken: cancelToken);
}
