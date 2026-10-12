import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/core/presentation/widgets/data_state_view.dart';
import 'package:mygalia/core/utils/date_format_fr.dart';
import 'package:mygalia/features/grades/domain/grade.dart';
import 'package:mygalia/features/grades/presentation/grades_controller.dart';

/// Notes du semestre, avec sélecteur de semestre et pull-to-refresh.
class GradesScreen extends ConsumerWidget {
  const GradesScreen({super.key, this.actions = const <Widget>[]});

  /// Actions supplémentaires de la barre d'application (menu du compte).
  final List<Widget> actions;

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
      appBar: AppBar(title: const Text('Notes'), actions: actions),
      body: Column(
        children: [
          if (periods.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: DropdownMenu<String>(
                key: ValueKey<String?>(selected),
                initialSelection: selected,
                expandedInsets: EdgeInsets.zero,
                label: const Text('Semestre'),
                dropdownMenuEntries: [
                  for (final SchoolPeriod p in periods)
                    DropdownMenuEntry<String>(
                      value: p.value,
                      label: p.shortLabel,
                      labelWidget: Text(p.label),
                    ),
                ],
                onSelected: (String? value) {
                  if (value == null) return;
                  ref.read(knownPeriodsProvider.notifier).state = periods;
                  ref.read(gradesPeriodProvider.notifier).state = value;
                },
              ),
            ),
          RefreshProgress(visible: state.isRefreshing),
          Expanded(
            child: DataStateView<GradesSnapshot>(
              state: state,
              onRefresh: controller.refresh,
              builder: (BuildContext context, GradesSnapshot snapshot) =>
                  snapshot.grades.isEmpty
                      ? const [_EmptyGrades()]
                      : [
                          for (final Grade grade in snapshot.grades)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _GradeCard(grade: grade),
                            ),
                        ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GradeCard extends StatelessWidget {
  const _GradeCard({required this.grade});

  final Grade grade;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final DateTime? date = grade.date;
    final String details = [
      if (grade.type != null) grade.type!,
      if (date != null) 'le ${DateFormatFr.date(date)}',
    ].join(' · ');
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
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(details, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text.rich(
                  TextSpan(
                    text: formatNumber(grade.value),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: grade.value < grade.outOf / 2
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurface,
                    ),
                    children: [
                      TextSpan(
                        text: ' /${formatNumber(grade.outOf)}',
                        style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                Text(
                  'coef. ${formatNumber(grade.coefficient)}',
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
              ],
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
          Icon(Icons.inbox_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('Aucune note pour ce semestre.', style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// « 12,5 », « 12 » (virgule décimale française).
String formatNumber(double value) {
  final String text = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  return text.replaceAll('.', ',');
}
