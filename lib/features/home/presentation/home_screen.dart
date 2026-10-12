import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/clock.dart';
import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/core/presentation/expressive/expressive_refresh_indicator.dart';
import 'package:mygalia/core/presentation/expressive/loading_indicator.dart';
import 'package:mygalia/core/presentation/expressive/material_shapes.dart';
import 'package:mygalia/core/presentation/expressive/shape_badge.dart';
import 'package:mygalia/core/presentation/expressive/wavy_progress_indicator.dart';
import 'package:mygalia/core/presentation/home_tabs.dart';
import 'package:mygalia/core/presentation/widgets/data_state_view.dart';
import 'package:mygalia/core/presentation/widgets/profile_shape.dart';
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
      body: ExpressiveRefreshIndicator(
        onRefresh: refreshAll,
        refreshing: week.isRefreshing || grades.isRefreshing,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ProfileShape(
                  email: email,
                  tooltip: 'Paramètres',
                  onTap: () => openTab(HomeTab.settings),
                ),
              ],
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
        return _HeroCard(
          shape: MaterialShapes.cookie6,
          danger: true,
          icon: icon,
          title: title,
          details: current.failure.message,
          action: TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        );
      }
      // Le cercle se transformera en la forme de l'état une fois chargé.
      return _HeroCard(
        shape: MaterialShapes.circle,
        icon: Icons.hourglass_empty_rounded,
        title: 'Chargement du planning…',
        progress: const WavyLinearProgressIndicator(semanticsLabel: 'Chargement du planning'),
      );
    }

    final Widget card;
    if (s.ongoing case final Course course) {
      final double total = course.end.difference(course.start).inSeconds.toDouble();
      final double elapsed = now.difference(course.start).inSeconds.toDouble();
      card = _HeroCard(
        shape: MaterialShapes.softBurst,
        accent: subjectColor(course.subject),
        icon: Icons.timelapse_rounded,
        label: 'EN COURS',
        title: course.subject,
        details: _timeAndRoom(course),
        progress: total <= 0
            ? null
            : WavyLinearProgressIndicator(
                value: (elapsed / total).clamp(0, 1).toDouble(),
                semanticsLabel: 'Avancement du cours',
              ),
        footer: 'Se termine dans ${DateFormatFr.duration(course.end.difference(now))}',
        onTap: () => onShowDay(course.day),
      );
    } else if (s.next case final Course course) {
      card = _HeroCard(
        shape: MaterialShapes.clover4,
        accent: subjectColor(course.subject),
        icon: Icons.schedule_rounded,
        label: 'À VENIR',
        title: course.subject,
        details: _timeAndRoom(course),
        footer: 'Commence dans ${DateFormatFr.duration(course.start.difference(now))}',
        onTap: () => onShowDay(course.day),
      );
    } else {
      final (MaterialShape shape, IconData icon, String title, String? message) = s.weekend
          ? (MaterialShapes.sunny, Icons.weekend_outlined, 'Week-end', 'Pas de cours aujourd\'hui.')
          : s.companyToday
              ? (
                  MaterialShapes.pentagon,
                  Icons.business_center_outlined,
                  'Présence en entreprise',
                  'Pas de cours à l\'école aujourd\'hui.',
                )
              : s.today.isEmpty
                  ? (
                      MaterialShapes.flower,
                      Icons.event_available_outlined,
                      'Pas de cours aujourd\'hui',
                      null,
                    )
                  : (
                      MaterialShapes.cookie9,
                      Icons.check_circle_outline_rounded,
                      'Journée terminée',
                      'Plus aucun cours prévu aujourd\'hui.',
                    );
      final Course? later = s.later;
      card = _HeroCard(
        shape: shape,
        icon: icon,
        title: title,
        details: message,
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

  static String _timeAndRoom(Course course) {
    final String? room = course.room;
    return '${DateFormatFr.time(course.start)} – ${DateFormatFr.time(course.end)}'
        '${room == null ? '' : ' · $room'}';
  }
}

/// Carte principale de l'accueil. Une seule carte pour tous les états :
/// sa forme se transforme de l'un à l'autre (chargement → à venir → en
/// cours → journée terminée…).
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.shape,
    required this.icon,
    required this.title,
    this.accent,
    this.danger = false,
    this.label,
    this.details,
    this.progress,
    this.footer,
    this.action,
    this.onTap,
  });

  final MaterialShape shape;
  final IconData icon;
  final String title;

  /// Couleur de la matière ; à défaut, couleurs primaires du thème.
  final Color? accent;

  /// Erreur : couleurs d'erreur.
  final bool danger;

  final String? label;
  final String? details;
  final Widget? progress;
  final String? footer;
  final Widget? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color muted = scheme.onSurfaceVariant;
    final Color? subject = accent;
    final (Color fill, Color ink) = danger
        ? (scheme.errorContainer, scheme.onErrorContainer)
        : subject != null
            ? (
                subject.withValues(alpha: theme.brightness == Brightness.dark ? 0.28 : 0.16),
                subject,
              )
            : (scheme.primaryContainer, scheme.onPrimaryContainer);
    final String? tag = label;
    final String? text = details;
    final Widget? bar = progress;
    final String? note = footer;
    final Widget? trailing = action;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShapeBadge(
                shape: shape,
                size: 56,
                color: fill,
                child: Icon(icon, color: ink, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (tag != null) ...[
                      Text(
                        tag,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      title,
                      style: tag != null
                          ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)
                          : theme.textTheme.titleMedium,
                    ),
                    if (text != null) ...[
                      SizedBox(height: tag != null ? 4 : 2),
                      Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                    ],
                    if (bar != null) ...[
                      const SizedBox(height: 10),
                      bar,
                    ],
                    if (note != null) ...[
                      const SizedBox(height: 8),
                      Text(note, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
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
    final ColorScheme scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ShapeBadge(
              shape: MaterialShapes.cookie7,
              size: 48,
              color: scheme.tertiaryContainer,
              child: Text(
                '$count',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                count <= 1 ? 'cours restant aujourd\'hui' : 'cours restants aujourd\'hui',
                style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
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
        padding: EdgeInsets.all(12),
        child: Center(
          child: ExpressiveLoadingIndicator(size: 40, semanticsLabel: 'Chargement des notes'),
        ),
      );
    }
    if (current is DataError<GradesSnapshot>) {
      final (IconData icon, String title) = describeFailure(current.failure);
      return _HeroCard(
        shape: MaterialShapes.cookie6,
        danger: true,
        icon: icon,
        title: title,
        details: current.failure.message,
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
            shape: MaterialShapes.cookie4,
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
            shape: MaterialShapes.gem,
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
    required this.shape,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final MaterialShape shape;
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
              ShapeBadge(
                shape: shape,
                size: 52,
                color: background,
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
