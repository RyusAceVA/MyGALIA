import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/clock.dart';
import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/core/presentation/home_tabs.dart';
import 'package:mygalia/core/presentation/widgets/data_state_view.dart';
import 'package:mygalia/core/presentation/widgets/section_title.dart';
import 'package:mygalia/core/utils/date_format_fr.dart';
import 'package:mygalia/features/auth/presentation/auth_controller.dart';
import 'package:mygalia/features/auth/presentation/sign_out_dialog.dart';
import 'package:mygalia/features/grades/domain/grade.dart';
import 'package:mygalia/features/grades/presentation/grades_controller.dart';
import 'package:mygalia/features/grades/presentation/grades_screen.dart';
import 'package:mygalia/features/home/domain/today_summary.dart';
import 'package:mygalia/features/schedule/domain/course.dart';
import 'package:mygalia/features/schedule/presentation/period_jump_controller.dart';
import 'package:mygalia/features/schedule/presentation/schedule_controller.dart';
import 'package:mygalia/features/schedule/presentation/schedule_screen.dart';
import 'package:mygalia/features/schedule/presentation/widgets/course_tile.dart';

/// Accueil : la journée en un coup d'œil (prochain cours, planning du jour,
/// dernières notes) et accès rapide.
///
/// Aucune requête de plus que les autres écrans : la semaine du jour et les
/// notes du semestre courant sont partagées avec l'emploi du temps et les
/// notes.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DateTime now = ref.watch(minuteTickProvider);
    // Le week-end, on regarde la semaine qui vient.
    final DateTime focusDay = weekdayOnOrAfter(now);
    final DateTime monday = mondayOf(focusDay);
    final DataState<WeekSchedule> week = ref.watch(scheduleControllerProvider(monday));
    final DataState<GradesSnapshot> grades = ref.watch(gradesControllerProvider(''));
    final AuthState auth = ref.watch(authControllerProvider);
    final String email = auth is AuthSignedIn ? auth.email : '';
    final WeekSchedule? weekData = week.data;
    final TodaySummary? summary = weekData == null ? null : TodaySummary.of(weekData, now);

    Future<void> refreshWeek() => ref.read(scheduleControllerProvider(monday).notifier).refresh();
    Future<void> refreshGrades() => ref.read(gradesControllerProvider('').notifier).refresh();
    Future<void> refreshAll() => Future.wait([refreshWeek(), refreshGrades()]);
    void openTab(HomeTab tab) => ref.read(homeTabProvider.notifier).state = tab;
    void showDay(DateTime day) {
      ref.read(scheduleSelectedDayProvider.notifier).state = weekdayOnOrAfter(day);
      openTab(HomeTab.schedule);
    }

    void findNextCourses() {
      openTab(HomeTab.schedule);
      announcePeriodSearch(
        context,
        ref.read(periodJumpControllerProvider.notifier).nextCourseDay(from: focusDay),
        next: true,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accueil'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.sync_rounded),
            onPressed: refreshAll,
          ),
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => confirmSignOut(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refreshAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
          children: [
            Text(
              DateFormatFr.dayLong(now),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Bonjour 👋',
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (email.isNotEmpty)
              Text(
                email,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            const SizedBox(height: 16),
            const SectionTitle('Prochain cours'),
            _NextCourseCard(
              state: week,
              summary: summary,
              now: now,
              onRetry: refreshWeek,
              onShowDay: showDay,
              onFindNext: findNextCourses,
            ),
            if (summary != null && !summary.weekend) ...[
              const SizedBox(height: 12),
              _RemainingTile(count: summary.remaining),
              const SizedBox(height: 16),
              SectionTitle(
                'Aujourd\'hui',
                actionLabel: 'Planning',
                onAction: () => showDay(now),
              ),
              if (summary.today.isEmpty)
                const _MutedLine('Aucun cours aujourd\'hui.')
              else
                for (final Course course in summary.today)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: CourseTile(
                      course: course,
                      highlighted: identical(course, summary.ongoing),
                    ),
                  ),
            ],
            const SizedBox(height: 16),
            SectionTitle(
              'Dernières notes',
              actionLabel: 'Toutes',
              onAction: () => openTab(HomeTab.grades),
            ),
            _LatestGrades(state: grades, onRetry: refreshGrades),
            const SizedBox(height: 16),
            const SectionTitle('Accès rapide'),
            _QuickAccess(
              onSchedule: () => showDay(now),
              onGrades: () => openTab(HomeTab.grades),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextCourseCard extends StatelessWidget {
  const _NextCourseCard({
    required this.state,
    required this.summary,
    required this.now,
    required this.onRetry,
    required this.onShowDay,
    required this.onFindNext,
  });

  final DataState<WeekSchedule> state;
  final TodaySummary? summary;
  final DateTime now;
  final Future<void> Function() onRetry;
  final ValueChanged<DateTime> onShowDay;
  final VoidCallback onFindNext;

  @override
  Widget build(BuildContext context) {
    final TodaySummary? s = summary;
    final DataState<WeekSchedule> current = state;
    if (s == null) {
      if (current is DataError<WeekSchedule>) {
        final (IconData icon, String title) = describeFailure(current.failure);
        return _InfoCard(
          icon: icon,
          title: title,
          message: current.failure.message,
          action: TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        );
      }
      return const _InfoCard(
        icon: Icons.hourglass_empty_rounded,
        title: 'Chargement du planning…',
        action: LinearProgressIndicator(),
      );
    }

    final Widget card;
    if (s.ongoing case final Course course) {
      final double total = course.end.difference(course.start).inSeconds.toDouble();
      final double elapsed = now.difference(course.start).inSeconds.toDouble();
      card = _CourseCard(
        label: 'EN COURS',
        icon: Icons.timelapse_rounded,
        course: course,
        footer: 'Se termine dans ${DateFormatFr.duration(course.end.difference(now))}',
        progress: total <= 0 ? null : (elapsed / total).clamp(0, 1).toDouble(),
        onTap: () => onShowDay(course.day),
      );
    } else if (s.next case final Course course) {
      card = _CourseCard(
        label: 'À VENIR',
        icon: Icons.schedule_rounded,
        course: course,
        footer: 'Commence dans ${DateFormatFr.duration(course.start.difference(now))}',
        onTap: () => onShowDay(course.day),
      );
    } else {
      final (IconData icon, String title, String? message) = s.weekend
          ? (Icons.weekend_outlined, 'Week-end', 'Pas de cours aujourd\'hui.')
          : s.companyToday
              ? (
                  Icons.business_center_outlined,
                  'Présence en entreprise',
                  'Pas de cours à l\'école aujourd\'hui.',
                )
              : s.today.isEmpty
                  ? (Icons.event_available_outlined, 'Pas de cours aujourd\'hui', null)
                  : (
                      Icons.check_circle_outline_rounded,
                      'Journée terminée',
                      'Plus aucun cours prévu aujourd\'hui.',
                    );
      final Course? later = s.later;
      card = _InfoCard(
        icon: icon,
        title: title,
        message: message,
        action: later != null
            ? TextButton.icon(
                onPressed: () => onShowDay(later.day),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(
                  'Prochain cours : ${DateFormatFr.dayInline(later.start)} à '
                  '${DateFormatFr.time(later.start)} — ${later.subject}',
                ),
              )
            : OutlinedButton.icon(
                onPressed: onFindNext,
                icon: const Icon(Icons.skip_next_rounded),
                label: const Text('Trouver les prochains cours'),
              ),
      );
    }

    final Failure? failure = current.failure;
    final DateTime? updatedAt = current.updatedAt;
    if (current is! DataCached<WeekSchedule> || failure == null || updatedAt == null) {
      return card;
    }
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: theme.colorScheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Planning ${DateFormatFr.updatedAt(updatedAt, now).replaceFirst('Mis à jour ', 'du ')}'
                  ' — rafraîchissement impossible',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              TextButton(onPressed: onRetry, child: const Text('Réessayer')),
            ],
          ),
        ),
      ],
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.label,
    required this.icon,
    required this.course,
    required this.footer,
    required this.onTap,
    this.progress,
  });

  final String label;
  final IconData icon;
  final Course course;
  final String footer;
  final VoidCallback onTap;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color muted = scheme.onSurfaceVariant;
    final String? room = course.room;
    final double? value = progress;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: subjectColor(course.subject).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: subjectColor(course.subject)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      course.subject,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${DateFormatFr.time(course.start)} – ${DateFormatFr.time(course.end)}'
                      '${room == null ? '' : ' · $room'}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                    if (value != null) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: value, minHeight: 6),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(footer, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? text = message;
    final Widget? trailing = action;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 36, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  if (text != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      text,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                  if (trailing != null) ...[
                    const SizedBox(height: 8),
                    trailing,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemainingTile extends StatelessWidget {
  const _RemainingTile({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Icon(Icons.event_note_outlined, size: 26, color: muted),
            const SizedBox(width: 16),
            Text(
              '$count',
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                count <= 1 ? 'cours restant aujourd\'hui' : 'cours restants aujourd\'hui',
                style: theme.textTheme.bodyLarge?.copyWith(color: muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LatestGrades extends StatelessWidget {
  const _LatestGrades({required this.state, required this.onRetry});

  final DataState<GradesSnapshot> state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final DataState<GradesSnapshot> current = state;
    if (current is DataLoading<GradesSnapshot>) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (current is DataError<GradesSnapshot>) {
      final (IconData icon, String title) = describeFailure(current.failure);
      return _InfoCard(
        icon: icon,
        title: title,
        message: current.failure.message,
        action: TextButton(onPressed: onRetry, child: const Text('Réessayer')),
      );
    }
    final List<Grade> latest =
        GradeStats.of(current.data?.grades ?? const <Grade>[]).byDate.take(3).toList();
    if (latest.isEmpty) return const _MutedLine('Aucune note pour l\'instant.');
    return Column(
      children: [
        for (final Grade grade in latest)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GradeTile(grade: grade),
          ),
      ],
    );
  }
}

class _QuickAccess extends StatelessWidget {
  const _QuickAccess({required this.onSchedule, required this.onGrades});

  final VoidCallback onSchedule;
  final VoidCallback onGrades;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: _QuickTile(
            icon: Icons.calendar_month_rounded,
            label: 'Emploi du temps',
            background: scheme.primaryContainer,
            foreground: scheme.onPrimaryContainer,
            onTap: onSchedule,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickTile(
            icon: Icons.school_rounded,
            label: 'Mes notes',
            background: dark ? const Color(0xFF134E48) : const Color(0xFFCCF2EC),
            foreground: dark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E),
            onTap: onGrades,
          ),
        ),
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: foreground),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MutedLine extends StatelessWidget {
  const _MutedLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
