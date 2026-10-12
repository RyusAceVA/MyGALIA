import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/core/presentation/widgets/data_state_view.dart';
import 'package:mygalia/core/utils/date_format_fr.dart';
import 'package:mygalia/features/schedule/domain/course.dart';
import 'package:mygalia/features/schedule/presentation/schedule_controller.dart';

/// Emploi du temps de la semaine, avec pull-to-refresh.
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key, this.actions = const <Widget>[]});

  /// Actions supplémentaires de la barre d'application (menu du compte).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DateTime monday = ref.watch(scheduleWeekProvider);
    final DataState<WeekSchedule> state =
        ref.watch(scheduleControllerProvider(monday));
    final ScheduleController controller =
        ref.read(scheduleControllerProvider(monday).notifier);
    final DateTime thisWeek = mondayOf(DateTime.now());

    void showWeek(DateTime target) =>
        ref.read(scheduleWeekProvider.notifier).state = target;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emploi du temps'),
        actions: [
          if (monday != thisWeek)
            IconButton(
              tooltip: 'Revenir à cette semaine',
              icon: const Icon(Icons.today_outlined),
              onPressed: () => showWeek(thisWeek),
            ),
          ...actions,
        ],
      ),
      body: Column(
        children: [
          _WeekBar(
            monday: monday,
            onPrevious: () =>
                showWeek(DateTime(monday.year, monday.month, monday.day - 7)),
            onNext: () =>
                showWeek(DateTime(monday.year, monday.month, monday.day + 7)),
          ),
          RefreshProgress(visible: state.isRefreshing),
          Expanded(
            child: DataStateView<WeekSchedule>(
              state: state,
              onRefresh: controller.refresh,
              builder: (BuildContext context, WeekSchedule week) => [
                for (int i = 0; i < 5; i++)
                  _DaySection(
                    day: DateTime(monday.year, monday.month, monday.day + i),
                    courses: week.coursesOn(
                      DateTime(monday.year, monday.month, monday.day + i),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekBar extends StatelessWidget {
  const _WeekBar({
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
              'Semaine ${DateFormatFr.weekRange(monday)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
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

class _DaySection extends StatelessWidget {
  const _DaySection({required this.day, required this.courses});

  final DateTime day;
  final List<Course> courses;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime now = DateTime.now();
    final bool isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isToday ? '${DateFormatFr.dayLong(day)} · aujourd\'hui' : DateFormatFr.dayLong(day),
            style: theme.textTheme.titleSmall?.copyWith(
              color: isToday ? theme.colorScheme.primary : null,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (courses.isEmpty)
            Text(
              'Pas de cours',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else
            for (final Course course in courses)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CourseCard(course: course),
              ),
        ],
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final String? teachers = course.teachers;
    final String? room = course.room;
    final String? group = course.group;
    return Card(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: subjectColor(course.subject)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${DateFormatFr.time(course.start)} – ${DateFormatFr.time(course.end)}',
                      style: theme.textTheme.labelLarge?.copyWith(color: muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      course.subject,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (teachers != null) ...[
                      const SizedBox(height: 2),
                      Text(teachers, style: theme.textTheme.bodyMedium),
                    ],
                    if (room != null || group != null) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          if (room != null) _Tag(icon: Icons.place_outlined, text: room),
                          if (group != null) _Tag(icon: Icons.groups_outlined, text: group),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: muted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ),
      ],
    );
  }
}

/// Couleur stable d'une matière, dérivée de son libellé (les données réelles
/// n'en fournissent pas, §3.3).
Color subjectColor(String subject) {
  const List<Color> palette = [
    Color(0xFF6366F1),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
  ];
  int hash = 0;
  for (final int unit in subject.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}
