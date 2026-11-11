import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/core/presentation/expressive/material_shapes.dart';
import 'package:mygalia/core/presentation/expressive/shape_badge.dart';
import 'package:mygalia/core/presentation/widgets/data_state_view.dart';
import 'package:mygalia/core/presentation/widgets/section_title.dart';
import 'package:mygalia/core/utils/date_format_fr.dart';
import 'package:mygalia/features/grades/domain/grade.dart';
import 'package:mygalia/features/grades/presentation/grades_controller.dart';

/// Notes : semestres, moyenne générale, meilleure / plus basse note, liste.
class GradesScreen extends ConsumerWidget {
  const GradesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String period = ref.watch(gradesPeriodProvider);
    final DataState<GradesSnapshot> state =
        ref.watch(gradesControllerProvider(period));
    final GradesController controller =
        ref.read(gradesControllerProvider(period).notifier);
    // Lu sans condition : le provider (autoDispose) vit autant que l'écran.
    final List<SchoolPeriod> known = ref.watch(knownPeriodsProvider);
    final List<SchoolPeriod> current = state.data?.periods ?? const <SchoolPeriod>[];
    // Pendant le chargement d'un autre semestre, le sélecteur reste affiché.
    final List<SchoolPeriod> periods = current.isNotEmpty ? current : known;
    final String? selected = period.isEmpty ? state.data?.selectedPeriod : period;

    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      body: Column(
        children: [
          if (periods.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _PeriodSelector(
                periods: periods,
                selected: selected,
                onSelected: (String value) {
                  ref.read(knownPeriodsProvider.notifier).state = periods;
                  ref.read(gradesPeriodProvider.notifier).state = value;
                },
              ),
            ),
          Expanded(
            child: DataStateView<GradesSnapshot>(
              state: state,
              onRefresh: controller.refresh,
              builder: (BuildContext context, GradesSnapshot snapshot) {
                if (snapshot.grades.isEmpty) return const [_EmptyGrades()];
                final GradeStats stats = GradeStats.of(snapshot.grades);
                return [
                  if (snapshot.unreadable > 0) ...[
                    _UnreadableNotice(count: snapshot.unreadable),
                    const SizedBox(height: 12),
                  ],
                  _SummaryCard(stats: stats),
                  const SizedBox(height: 16),
                  const SectionTitle('Toutes les notes'),
                  for (final Grade grade in stats.byDate)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GradeTile(grade: grade),
                    ),
                ];
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.periods,
    required this.selected,
    required this.onSelected,
  });

  final List<SchoolPeriod> periods;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final String? value = selected;
    if (periods.length > 3) {
      // Beaucoup de semestres : puces défilantes.
      return SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final SchoolPeriod p in periods)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(p.name),
                  selected: p.value == value,
                  onSelected: (_) => onSelected(p.value),
                ),
              ),
          ],
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        emptySelectionAllowed: value == null,
        segments: [
          for (final SchoolPeriod p in periods)
            ButtonSegment<String>(
              value: p.value,
              tooltip: p.label,
              label: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        selected: value == null ? <String>{} : {value},
        onSelectionChanged: (Set<String> selection) {
          if (selection.isNotEmpty) onSelected(selection.first);
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.stats});

  final GradeStats stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final double? average = stats.average;
    final int count = stats.byDate.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GradeShape(
                  on20: average,
                  text: average == null ? '—' : formatNumber(average),
                  outOf: '/ 20',
                  size: 112,
                  large: true,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MOYENNE GÉNÉRALE',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: muted, letterSpacing: 1.6),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        count <= 1 ? '$count note' : '$count notes',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Moyenne pondérée par les coefficients',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _StatColumn(
                    icon: Icons.trending_up_rounded,
                    label: 'Meilleure',
                    grade: stats.best,
                    color: successColor(theme),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _StatColumn(
                    icon: Icons.trending_down_rounded,
                    label: 'Plus basse',
                    grade: stats.worst,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.icon,
    required this.label,
    required this.grade,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Grade? grade;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final Grade? value = grade;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(color: muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value?.on20 == null ? '—' : formatNumber(value!.on20!),
          style: theme.textTheme.headlineMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
        if (value != null)
          Text(
            value.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
      ],
    );
  }
}

/// Une note : matière, type, date, coefficient et valeur colorée.
class GradeTile extends StatelessWidget {
  const GradeTile({super.key, required this.grade});

  final Grade grade;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final DateTime? date = grade.date;
    final String? type = grade.type;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    grade.subject,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (type != null)
                    Text(type, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                  const SizedBox(height: 6),
                  // Wrap : date et coefficient passent à la ligne si besoin.
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (date != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_outlined, size: 14, color: muted),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                DateFormatFr.dateLong(date),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(color: muted),
                              ),
                            ),
                          ],
                        ),
                      Text(
                        'coef. ${formatNumber(grade.coefficient)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            GradeShape(
              on20: grade.on20,
              text: grade.value == null
                  ? (grade.mention ?? '—')
                  : formatNumber(grade.value!),
              outOf: grade.value == null ? null : '/ ${formatNumber(grade.outOf)}',
            ),
          ],
        ),
      ),
    );
  }
}

/// Des évaluations de la page n'ont pas été comprises : la moyenne affichée
/// peut être incomplète, autant le dire.
class _UnreadableNotice extends StatelessWidget {
  const _UnreadableNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                count == 1
                    ? "1 évaluation de l'espace école n'a pas pu être lue : "
                        'la moyenne peut être incomplète.'
                    : "$count évaluations de l'espace école n'ont pas pu être "
                        'lues : la moyenne peut être incomplète.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyGrades extends StatelessWidget {
  const _EmptyGrades();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 96),
      child: Column(
        children: [
          ShapeBadge(
            shape: MaterialShapes.clover8,
            initialShape: MaterialShapes.circle,
            size: 96,
            color: theme.colorScheme.secondaryContainer,
            child: Icon(
              Icons.inbox_outlined,
              size: 40,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 16),
          Text('Aucune note pour ce semestre.', style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// Note (ou moyenne) dans une forme Material 3 Expressive : biscuit, ou
/// soleil dès 16 sur 20 ; vert dès 14, rouge sous 10.
class GradeShape extends StatelessWidget {
  const GradeShape({
    super.key,
    required this.on20,
    required this.text,
    required this.outOf,
    this.size = 64,
    this.large = false,
  });

  /// Valeur ramenée sur 20 (couleur et forme) ; nulle : neutre.
  final double? on20;
  final String text;

  /// Barème (« / 20 ») ; absent pour une mention sans note.
  final String? outOf;
  final double size;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (Color fill, Color ink) = gradeContainerColors(theme, on20);
    final double? value = on20;
    return ShapeBadge(
      shape: value != null && value >= 16 ? MaterialShapes.sunny : MaterialShapes.cookie9,
      initialShape: large ? MaterialShapes.circle : null,
      size: size,
      color: fill,
      child: Padding(
        // Le texte reste dans le disque intérieur de la forme.
        padding: EdgeInsets.all(size * 0.17),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                style: (large ? theme.textTheme.headlineMedium : theme.textTheme.titleMedium)
                    ?.copyWith(color: ink, fontWeight: FontWeight.w800, height: 1.1),
              ),
              if (outOf case final String scale)
                Text(
                  scale,
                  style: (large ? theme.textTheme.labelLarge : theme.textTheme.labelSmall)
                      ?.copyWith(color: ink.withValues(alpha: 0.8), height: 1.1),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fond et encre d'une forme portant une note sur 20.
(Color, Color) gradeContainerColors(ThemeData theme, double? on20) {
  final ColorScheme scheme = theme.colorScheme;
  final double? value = on20;
  if (value == null) return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
  if (value >= 14) {
    final Color success = successColor(theme);
    return (
      success.withValues(alpha: theme.brightness == Brightness.dark ? 0.24 : 0.16),
      success,
    );
  }
  if (value < 10) return (scheme.errorContainer, scheme.onErrorContainer);
  return (scheme.secondaryContainer, scheme.onSecondaryContainer);
}

/// Vert lisible en clair comme en sombre.
Color successColor(ThemeData theme) => theme.brightness == Brightness.dark
    ? const Color(0xFF4ADE80)
    : const Color(0xFF16A34A);

/// « 12,5 », « 12 », « 16,75 » (virgule décimale française).
String formatNumber(double value) {
  final String text = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  return text.replaceAll('.', ',');
}
