import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/core/presentation/expressive/loading_indicator.dart';
import 'package:mygalia/core/presentation/expressive/material_shapes.dart';
import 'package:mygalia/core/presentation/expressive/shape_badge.dart';
import 'package:mygalia/core/presentation/widgets/data_state_view.dart';
import 'package:mygalia/core/utils/date_format_fr.dart';
import 'package:mygalia/features/schedule/data/calendar_exporter.dart';
import 'package:mygalia/features/schedule/domain/course.dart';
import 'package:mygalia/features/schedule/presentation/period_jump_controller.dart';
import 'package:mygalia/features/schedule/presentation/schedule_controller.dart';
import 'package:mygalia/features/schedule/presentation/widgets/course_tile.dart';

/// Emploi du temps : semaine, bande des jours, séances du jour choisi,
/// saut de période de cours en période de cours, pull-to-refresh.
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DateTime selected = ref.watch(scheduleSelectedDayProvider);
    final DateTime monday = mondayOf(selected);
    final DataState<WeekSchedule> state = ref.watch(scheduleControllerProvider(monday));
    final ScheduleController controller =
        ref.read(scheduleControllerProvider(monday).notifier);
    final PeriodJumpDirection? searching = ref.watch(periodJumpControllerProvider);

    void select(DateTime day) =>
        ref.read(scheduleSelectedDayProvider.notifier).state = weekdayOnOrAfter(day);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emploi du temps'),
        actions: [
          IconButton(
            tooltip: "Exporter la semaine vers l'agenda",
            icon: const Icon(Icons.event_available_outlined),
            onPressed: () => _export(context, ref, state.data),
          ),
          IconButton(
            tooltip: 'Choisir une date',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => _pickDate(context, selected, select),
          ),
          IconButton(
            tooltip: 'Aujourd\'hui',
            icon: const Icon(Icons.today_outlined),
            onPressed: () => select(DateTime.now()),
          ),
        ],
      ),
      body: Column(
        children: [
          _WeekHeader(
            monday: monday,
            onPrevious: () =>
                select(DateTime(selected.year, selected.month, selected.day - 7)),
            onNext: () =>
                select(DateTime(selected.year, selected.month, selected.day + 7)),
          ),
          _DayStrip(
            monday: monday,
            selected: selected,
            week: state.data,
            onSelected: select,
          ),
          _PeriodJumpBar(
            searching: searching,
            onJump: (PeriodJumpDirection direction) =>
                jumpToPeriod(context, ref, from: selected, direction: direction),
          ),
          SearchProgressBar(
            visible: searching != null,
            semanticsLabel: 'Recherche des cours',
          ),
          Expanded(
            // Balayer horizontalement change de jour (et de semaine aux bords).
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (DragEndDetails details) {
                final double velocity = details.primaryVelocity ?? 0;
                if (velocity < -250) select(nextWeekday(selected));
                if (velocity > 250) select(previousWeekday(selected));
              },
              child: DataStateView<WeekSchedule>(
                state: state,
                onRefresh: controller.refresh,
                builder: (BuildContext context, WeekSchedule week) =>
                    _dayContent(week, selected, select),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static List<Widget> _dayContent(
    WeekSchedule week,
    DateTime day,
    ValueChanged<DateTime> select,
  ) {
    final List<Course> courses = week.coursesOn(day);
    if (courses.isEmpty) {
      final DateTime endOfDay = DateTime(day.year, day.month, day.day + 1);
      return [
        _EmptyDay(next: firstSchoolCourseAfter(week, endOfDay), onShow: select),
      ];
    }
    return [
      for (final Course course in courses)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: CourseTile(course: course),
        ),
    ];
  }

  /// Remet les cours de la semaine affichée à l'agenda du téléphone.
  static Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    WeekSchedule? week,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    void say(String message) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    if (week == null) {
      say("Le planning de cette semaine n'est pas encore chargé.");
      return;
    }
    switch (await ref.read(calendarExporterProvider)(week)) {
      case CalendarExportResult.shared:
        break;
      case CalendarExportResult.nothingToExport:
        say('Aucun cours à exporter cette semaine.');
      case CalendarExportResult.failed:
        say('Export impossible. Réessayez.');
    }
  }

  static Future<void> _pickDate(
    BuildContext context,
    DateTime initial,
    ValueChanged<DateTime> select,
  ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 2),
      lastDate: DateTime(initial.year + 2, 12, 31),
      selectableDayPredicate: (DateTime day) => day.weekday <= DateTime.friday,
      helpText: 'Aller au jour',
    );
    if (picked != null) select(picked);
  }
}

/// Lance un saut de période et en annonce l'issue (barre de notification).
Future<void> jumpToPeriod(
  BuildContext context,
  WidgetRef ref, {
  required DateTime from,
  required PeriodJumpDirection direction,
}) =>
    announcePeriodSearch(
      context,
      ref.read(periodJumpControllerProvider.notifier).jump(from: from, direction: direction),
      next: direction == PeriodJumpDirection.next,
    );

/// Annonce l'issue d'une recherche de cours (barre de notification).
Future<void> announcePeriodSearch(
  BuildContext context,
  Future<PeriodJumpResult> search, {
  required bool next,
}) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final PeriodJumpResult result = await search;
  final String? message = switch (result) {
    PeriodFound(:final DateTime day) =>
      '${next ? 'Prochains cours' : 'Période précédente'} : ${DateFormatFr.dayInline(day)}',
    PeriodNotFound() => next
        ? 'Aucun cours trouvé dans les 12 prochaines semaines.'
        : 'Aucun cours trouvé dans les 12 semaines précédentes.',
    PeriodJumpFailed(:final failure) => failure.message,
    PeriodJumpCancelled() => null,
  };
  if (message == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({
    required this.monday,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime monday;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Semaine précédente',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: onPrevious,
          ),
          Expanded(
            child: Text(
              DateFormatFr.weekRangeShort(monday),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'Semaine suivante',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _DayStrip extends StatelessWidget {
  const _DayStrip({
    required this.monday,
    required this.selected,
    required this.week,
    required this.onSelected,
  });

  final DateTime monday;
  final DateTime selected;
  final WeekSchedule? week;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final DateTime today = dateOnly(DateTime.now());
    final WeekSchedule? data = week;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          for (int i = 0; i < 5; i++)
            Expanded(
              child: _DayChip(
                day: DateTime(monday.year, monday.month, monday.day + i),
                selected: DateTime(monday.year, monday.month, monday.day + i) == selected,
                isToday: DateTime(monday.year, monday.month, monday.day + i) == today,
                kind: data == null
                    ? null
                    : dayKindOf(data.coursesOn(DateTime(monday.year, monday.month, monday.day + i))),
                onTap: onSelected,
              ),
            ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.kind,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final DayKind? kind;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color foreground = selected
        ? scheme.onSecondaryContainer
        : (isToday ? scheme.primary : scheme.onSurface);
    const BorderRadius radius = BorderRadius.all(Radius.circular(18));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Semantics(
        selected: selected,
        button: true,
        label: DateFormatFr.dayLong(day),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected ? scheme.secondaryContainer : scheme.secondaryContainer.withValues(alpha: 0),
            borderRadius: radius,
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: () => onTap(day),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormatFr.weekdayShort(day),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: selected || isToday ? foreground : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${day.day}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: foreground,
                      fontWeight: selected || isToday ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _KindMarker(kind: kind, color: foreground),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Point sous un jour de cours, petit losange creux pour l'entreprise.
class _KindMarker extends StatelessWidget {
  const _KindMarker({required this.kind, required this.color});

  final DayKind? kind;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 8,
      child: switch (kind) {
        DayKind.school => Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        DayKind.company => Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: scheme.outline, width: 1.2),
            ),
          ),
        DayKind.empty || null => const SizedBox(width: 6),
      },
    );
  }
}

class _PeriodJumpBar extends StatelessWidget {
  const _PeriodJumpBar({required this.searching, required this.onJump});

  final PeriodJumpDirection? searching;
  final ValueChanged<PeriodJumpDirection> onJump;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      // Boutons flexibles : sur un petit écran (ou en grand texte), le
      // libellé s'abrège au lieu de déborder.
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: _JumpButton(
              label: 'Cours précédents',
              icon: Icons.skip_previous_rounded,
              iconAtEnd: false,
              searching: searching == PeriodJumpDirection.previous,
              onPressed: searching == PeriodJumpDirection.next
                  ? null
                  : () => onJump(PeriodJumpDirection.previous),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: _JumpButton(
              label: 'Prochains cours',
              icon: Icons.skip_next_rounded,
              iconAtEnd: true,
              searching: searching == PeriodJumpDirection.next,
              onPressed: searching == PeriodJumpDirection.previous
                  ? null
                  : () => onJump(PeriodJumpDirection.next),
            ),
          ),
        ],
      ),
    );
  }
}

class _JumpButton extends StatelessWidget {
  const _JumpButton({
    required this.label,
    required this.icon,
    required this.iconAtEnd,
    required this.searching,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool iconAtEnd;
  final bool searching;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      iconAlignment: iconAtEnd ? IconAlignment.end : IconAlignment.start,
      icon: searching
          ? const ExpressiveLoadingIndicator(size: 22, semanticsLabel: 'Recherche en cours')
          : Icon(icon),
      // L'indicateur à formes dit « recherche en cours » ; le libellé
      // dit ce que fait l'appui, sans être tronqué sur un petit écran.
      label: Text(
        searching ? 'Annuler' : label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.next, required this.onShow});

  final Course? next;
  final ValueChanged<DateTime> onShow;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Course? upcoming = next;
    return Padding(
      padding: const EdgeInsets.only(top: 72),
      child: Column(
        children: [
          ShapeBadge(
            shape: MaterialShapes.flower,
            initialShape: MaterialShapes.circle,
            size: 96,
            color: theme.colorScheme.secondaryContainer,
            child: Icon(
              Icons.event_available_outlined,
              size: 40,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 16),
          Text('Pas de cours ce jour', style: theme.textTheme.titleMedium),
          if (upcoming != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => onShow(upcoming.day),
              child: Text(
                'Prochain cours : ${DateFormatFr.dayInline(upcoming.start)} '
                'à ${DateFormatFr.time(upcoming.start)}',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
