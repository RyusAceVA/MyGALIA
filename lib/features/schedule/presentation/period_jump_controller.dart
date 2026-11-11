import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
/// Respect du serveur (une semaine coûte cinq requêtes) :
///  * une semaine passée déjà en cache n'est jamais redemandée : elle ne
///    changera plus ;
///  * une semaine à venir en cache depuis moins de [cacheValidity] non plus :
///    la recherche ne veut savoir que « cours ou entreprise », et le rythme
///    de l'alternance ne bouge pas d'un jour à l'autre. La semaine trouvée
///    est de toute façon rafraîchie par l'écran qui l'affiche ;
///  * les semaines manquantes sont chargées une à une, avec une pause de
///    [pauseBetweenFetches] entre deux, et la recherche s'arrête à 12
///    semaines.
/// Un nouvel appui pendant la recherche l'annule.
class PeriodJumpController extends Notifier<PeriodJumpDirection?> {
  static const Duration cacheValidity = Duration(days: 7);

  /// Pause entre deux semaines demandées au serveur pendant une recherche.
  @visibleForTesting
  static Duration pauseBetweenFetches = const Duration(milliseconds: 400);

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
      int fetched = 0;
      final CoursePeriodFinder finder = CoursePeriodFinder((DateTime monday) async {
        final WeekSchedule? cached = usableCache(repository, monday, DateTime.now());
        if (token.isCancelled) throw const CancelledFailure();
        if (cached != null) return cached;
        if (fetched++ > 0) {
          await Future<void>.delayed(pauseBetweenFetches);
          if (token.isCancelled) throw const CancelledFailure();
        }
        return (await repository.fetchWeek(monday, cancelToken: token)).data;
      });
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

  /// Semaine en cache suffisante pour une recherche, ou `null`.
  @visibleForTesting
  static WeekSchedule? usableCache(
    ScheduleRepository repository,
    DateTime monday,
    DateTime now,
  ) {
    final CachedValue<WeekSchedule>? cached = repository.cachedWeek(monday);
    if (cached == null) return null;
    // Semaine entièrement passée au moment de l'enregistrement : figée.
    final DateTime saturday = DateTime(monday.year, monday.month, monday.day + 5);
    if (!cached.savedAt.isBefore(saturday)) return cached.data;
    return now.difference(cached.savedAt) < cacheValidity ? cached.data : null;
  }
}
