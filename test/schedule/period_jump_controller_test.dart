import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/storage/cache_store.dart';
import 'package:mygalia/features/schedule/data/schedule_repository.dart';
import 'package:mygalia/features/schedule/domain/course.dart';
import 'package:mygalia/features/schedule/presentation/period_jump_controller.dart';
import 'package:mygalia/features/schedule/presentation/schedule_controller.dart';

DateTime _w(int week) => DateTime(2026, 10, 12 + 7 * week);

List<Course> _days(DateTime monday, String subject) => [
      for (int d = 0; d < 5; d++)
        Course(
          start: DateTime(monday.year, monday.month, monday.day + d, 8, 30),
          end: DateTime(monday.year, monday.month, monday.day + d, 12),
          subject: subject,
        ),
    ];

/// Dépôt factice : semaines en mémoire, cache facultatif, réseau compté.
class _FakeRepository implements ScheduleRepository {
  _FakeRepository(this.weeks, {Map<DateTime, CachedValue<WeekSchedule>>? cached})
      : cached = cached ?? <DateTime, CachedValue<WeekSchedule>>{};

  final Map<DateTime, List<Course>> weeks;
  final Map<DateTime, CachedValue<WeekSchedule>> cached;
  int fetches = 0;
  Completer<void>? gate;

  @override
  CachedValue<WeekSchedule>? cachedWeek(DateTime monday) => cached[monday];

  @override
  Future<CachedValue<WeekSchedule>> fetchWeek(
    DateTime monday, {
    CancelToken? cancelToken,
  }) async {
    fetches++;
    await gate?.future;
    if (cancelToken?.isCancelled ?? false) throw const CancelledFailure();
    return CachedValue<WeekSchedule>(
      WeekSchedule(monday: monday, courses: weeks[monday] ?? const <Course>[]),
      DateTime.now(),
    );
  }
}

void main() {
  late _FakeRepository repository;
  late ProviderContainer container;

  setUp(() {
    PeriodJumpController.pauseBetweenFetches = Duration.zero;
    // Semaine 0 et 1 en entreprise, semaine 2 à l'école.
    repository = _FakeRepository({
      _w(0): _days(_w(0), 'Presence en entreprise'),
      _w(1): _days(_w(1), 'Presence en entreprise'),
      _w(2): _days(_w(2), 'DEVELOPPEMENT WEB'),
    });
    container = ProviderContainer(
      overrides: [scheduleRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() => container.dispose());

  test('prochains cours : saut au premier jour de la période et jour affiché', () async {
    final PeriodJumpResult result = await container
        .read(periodJumpControllerProvider.notifier)
        .jump(from: _w(0), direction: PeriodJumpDirection.next);

    expect(result, isA<PeriodFound>());
    expect((result as PeriodFound).day, _w(2));
    expect(container.read(scheduleSelectedDayProvider), _w(2));
    expect(container.read(periodJumpControllerProvider), isNull);
  });

  test('une semaine récente en cache n\'est pas redemandée au serveur', () async {
    repository.cached[_w(1)] = CachedValue<WeekSchedule>(
      WeekSchedule(monday: _w(1), courses: _days(_w(1), 'Presence en entreprise')),
      DateTime.now(),
    );

    await container
        .read(periodJumpControllerProvider.notifier)
        .jump(from: _w(0), direction: PeriodJumpDirection.next);

    expect(repository.fetches, 2, reason: 'semaines 0 et 2 seulement');
  });

  test('un second appui annule la recherche en cours', () async {
    repository.gate = Completer<void>();
    final PeriodJumpController controller =
        container.read(periodJumpControllerProvider.notifier);

    final Future<PeriodJumpResult> first =
        controller.jump(from: _w(0), direction: PeriodJumpDirection.next);
    expect(container.read(periodJumpControllerProvider), PeriodJumpDirection.next);
    final PeriodJumpResult second =
        await controller.jump(from: _w(0), direction: PeriodJumpDirection.next);
    repository.gate!.complete();

    expect(second, isA<PeriodJumpCancelled>());
    expect(await first, isA<PeriodJumpCancelled>());
    expect(container.read(periodJumpControllerProvider), isNull);
  });

  test('rien trouvé : résultat explicite, jour affiché inchangé', () async {
    repository.weeks.remove(_w(2));
    final DateTime before = container.read(scheduleSelectedDayProvider);

    final PeriodJumpResult result = await container
        .read(periodJumpControllerProvider.notifier)
        .jump(from: _w(0), direction: PeriodJumpDirection.next);

    expect(result, isA<PeriodNotFound>());
    expect(container.read(scheduleSelectedDayProvider), before);
  });

  group('cache utilisable pour une recherche', () {
    final DateTime monday = DateTime(2026, 10, 12);
    WeekSchedule week() => WeekSchedule(monday: monday, courses: const <Course>[]);
    _FakeRepository withCache(DateTime savedAt) => _FakeRepository(
          const <DateTime, List<Course>>{},
          cached: {monday: CachedValue<WeekSchedule>(week(), savedAt)},
        );

    test('semaine à venir : valable sept jours, pas davantage', () {
      final DateTime savedAt = DateTime(2026, 10, 1, 9);

      expect(
        PeriodJumpController.usableCache(withCache(savedAt), monday, DateTime(2026, 10, 7)),
        isNotNull,
      );
      expect(
        PeriodJumpController.usableCache(withCache(savedAt), monday, DateTime(2026, 10, 9)),
        isNull,
      );
    });

    test('semaine enregistrée après sa fin : figée, jamais redemandée', () {
      final _FakeRepository repository = withCache(DateTime(2026, 10, 17, 8));

      expect(
        PeriodJumpController.usableCache(repository, monday, DateTime(2027, 6, 1)),
        isNotNull,
      );
    });

    test('semaine enregistrée en cours de route : redemandée une fois ancienne', () {
      final _FakeRepository repository = withCache(DateTime(2026, 10, 14, 8));

      expect(
        PeriodJumpController.usableCache(repository, monday, DateTime(2026, 11, 1)),
        isNull,
      );
    });

    test('pas de cache : rien', () {
      expect(
        PeriodJumpController.usableCache(
          _FakeRepository(const <DateTime, List<Course>>{}),
          monday,
          DateTime(2026, 10, 12),
        ),
        isNull,
      );
    });
  });

  test('pause entre deux semaines demandées, jamais avant la première', () async {
    PeriodJumpController.pauseBetweenFetches = const Duration(milliseconds: 120);
    final Stopwatch watch = Stopwatch()..start();

    await container
        .read(periodJumpControllerProvider.notifier)
        .jump(from: _w(0), direction: PeriodJumpDirection.next);

    // Trois semaines demandées : deux pauses.
    expect(repository.fetches, 3);
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(240));
  });
}
