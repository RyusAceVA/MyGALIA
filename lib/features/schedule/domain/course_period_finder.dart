import 'package:mygalia/features/schedule/domain/course.dart';

/// Charge une semaine (cache récent ou réseau).
typedef WeekLoader = Future<WeekSchedule> Function(DateTime monday);

/// Navigation « de période de cours en période de cours » (alternance).
///
/// Une **période de cours** est une suite de jours de cours à l'école. Les
/// week-ends et les jours sans rien ne l'interrompent pas ; elle se termine
/// par de la présence en entreprise, ou par une coupure d'au moins
/// [holidayBreak] jours ouvrés sans rien (vacances).
///
/// Les semaines sont chargées une à une, dans l'ordre, et seulement si
/// nécessaire ; la recherche s'arrête à [maxWeeks] semaines.
class CoursePeriodFinder {
  CoursePeriodFinder(this._loadWeek, {this.maxWeeks = 12});

  static const int holidayBreak = 3;

  final WeekLoader _loadWeek;
  final int maxWeeks;
  final Map<DateTime, WeekSchedule> _weeks = <DateTime, WeekSchedule>{};

  /// Premier jour de la prochaine période de cours après [from] (si [from]
  /// est un jour de cours, la période en cours est d'abord dépassée), ou
  /// `null` si aucune dans les [maxWeeks] semaines.
  Future<DateTime?> nextPeriodStart(DateTime from) async {
    final DateTime start = dateOnly(from);
    final DateTime monday = mondayOf(start);
    final DateTime limit = DateTime(monday.year, monday.month, monday.day + 7 * maxWeeks);
    bool leftCurrentPeriod = await _kind(start) != DayKind.school;
    int emptyRun = 0;
    for (DateTime day = nextWeekday(start); day.isBefore(limit); day = nextWeekday(day)) {
      switch (await _kind(day)) {
        case DayKind.school:
          if (leftCurrentPeriod) return day;
          emptyRun = 0;
        case DayKind.company:
          leftCurrentPeriod = true;
          emptyRun = 0;
        case DayKind.empty:
          if (++emptyRun >= holidayBreak) leftCurrentPeriod = true;
      }
    }
    return null;
  }

  /// Premier jour de la période de cours précédente (si [from] est dans une
  /// période de cours, c'est celle d'avant), ou `null`.
  Future<DateTime?> previousPeriodStart(DateTime from) async {
    final DateTime start = dateOnly(from);
    final DateTime monday = mondayOf(start);
    final DateTime limit = DateTime(monday.year, monday.month, monday.day - 7 * maxWeeks);
    _Phase phase = await _kind(start) == DayKind.school ? _Phase.current : _Phase.gap;
    DateTime? candidate;
    int emptyRun = 0;
    for (DateTime day = previousWeekday(start); !day.isBefore(limit); day = previousWeekday(day)) {
      final DayKind kind = await _kind(day);
      switch (phase) {
        case _Phase.current:
          // Remonter jusqu'au début de la période en cours.
          if (kind == DayKind.school) {
            emptyRun = 0;
          } else if (kind == DayKind.company || ++emptyRun >= holidayBreak) {
            phase = _Phase.gap;
            emptyRun = 0;
          }
        case _Phase.gap:
          // Entreprise ou vacances : chercher la fin de la période d'avant.
          if (kind == DayKind.school) {
            phase = _Phase.previous;
            candidate = day;
          }
        case _Phase.previous:
          // Remonter jusqu'au premier jour de cette période.
          if (kind == DayKind.school) {
            candidate = day;
            emptyRun = 0;
          } else if (kind == DayKind.company || ++emptyRun >= holidayBreak) {
            return candidate;
          }
      }
    }
    return phase == _Phase.previous ? candidate : null;
  }

  Future<DayKind> _kind(DateTime day) async {
    final DateTime monday = mondayOf(day);
    final WeekSchedule week = _weeks[monday] ??= await _loadWeek(monday);
    return dayKindOf(week.coursesOn(day));
  }
}

enum _Phase { current, gap, previous }
