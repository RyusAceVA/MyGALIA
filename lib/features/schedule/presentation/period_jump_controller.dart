import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/storage/cache_store.dart';
import 'package:mygalia/features/schedule/data/schedule_repository.dart';
import 'package:mygalia/features/schedule/domain/course.dart';
import 'package:mygalia/features/schedule/domain/course_period_finder.dart';
import 'package:mygalia/features/schedule/presentation/schedule_controller.dart';

enum PeriodJumpDirection { previous, next }

/// Issue d'un saut de période.
sealed class PeriodJumpResult {
  const PeriodJumpResult();
}

final class PeriodFound extends PeriodJumpResult {
  const PeriodFound(this.day);

  final DateTime day;
}

final class PeriodNotFound extends PeriodJumpResult {
  const PeriodNotFound();
}

final class PeriodJumpCancelled extends PeriodJumpResult {
  const PeriodJumpCancelled();
}

final class PeriodJumpFailed extends PeriodJumpResult {
  const PeriodJumpFailed(this.failure);

  final Failure failure;
}

/// Recherche en cours (direction), ou `null`.
final periodJumpControllerProvider =
    NotifierProvider<PeriodJumpController, PeriodJumpDirection?>(
  PeriodJumpController.new,
);

/// Saut « de période de cours en période de cours » dans l'emploi du temps.
///
/// Respect du serveur : une semaine déjà en cache depuis moins de
/// [cacheValidity] n'est pas redemandée, les semaines sont chargées une à
/// une, et la recherche s'arrête à 12 semaines. Un nouvel appui pendant la
/// recherche l'annule.
class PeriodJumpController extends Notifier<PeriodJumpDirection?> {
  static const Duration cacheValidity = Duration(hours: 12);

  CancelToken? _token;

  @override
  PeriodJumpDirection? build() {
    ref.onDispose(() => _token?.cancel());
    return null;
  }

  /// Saut au premier jour de la période de cours suivante / précédente.
  Future<PeriodJumpResult> jump({
    required DateTime from,
    required PeriodJumpDirection direction,
  }) =>
      _search(
        direction,
        'saut de période (${direction.name}) depuis ${from.day}/${from.month}',
        (CoursePeriodFinder finder) => direction == PeriodJumpDirection.next
            ? finder.nextPeriodStart(from)
            : finder.previousPeriodStart(from),
      );

  /// Premier jour de cours après [from], même dans la période en cours
  /// (accueil : « Trouver les prochains cours »).
  Future<PeriodJumpResult> nextCourseDay({required DateTime from}) => _search(
        PeriodJumpDirection.next,
        'recherche du prochain jour de cours depuis ${from.day}/${from.month}',
        (CoursePeriodFinder finder) => finder.nextSchoolDay(from),
      );

  Future<PeriodJumpResult> _search(
    PeriodJumpDirection direction,
    String label,
    Future<DateTime?> Function(CoursePeriodFinder finder) search,
  ) async {
    if (state != null) {
      cancel();
      return const PeriodJumpCancelled();
    }
    final CancelToken token = CancelToken();
    _token = token;
    state = direction;
    AppLog.lifecycle(label);
    try {
      final ScheduleRepository repository = ref.read(scheduleRepositoryProvider);
      final CoursePeriodFinder finder =
          CoursePeriodFinder((DateTime monday) => _loadWeek(repository, monday, token));
      final DateTime? day = await search(finder);
      if (token.isCancelled) return const PeriodJumpCancelled();
      if (day == null) return const PeriodNotFound();
      ref.read(scheduleSelectedDayProvider.notifier).state = day;
      return PeriodFound(day);
    } on CancelledFailure {
      return const PeriodJumpCancelled();
    } on Failure catch (failure) {
      return PeriodJumpFailed(failure);
    } finally {
      if (identical(_token, token)) {
        _token = null;
        state = null;
      }
    }
  }

  void cancel() {
    _token?.cancel('recherche annulée');
    _token = null;
    state = null;
  }

  static Future<WeekSchedule> _loadWeek(
    ScheduleRepository repository,
    DateTime monday,
    CancelToken token,
  ) async {
    if (token.isCancelled) throw const CancelledFailure();
    final CachedValue<WeekSchedule>? cached = repository.cachedWeek(monday);
    if (cached != null && DateTime.now().difference(cached.savedAt) < cacheValidity) {
      return cached.data;
    }
    return (await repository.fetchWeek(monday, cancelToken: token)).data;
  }
}
