import 'package:flutter/material.dart';

import 'package:mygalia/core/utils/date_format_fr.dart';
import 'package:mygalia/features/schedule/domain/course.dart';

/// Carte d'une séance : horaires, matière, formateur, salle, groupe.
/// La présence en entreprise est affichée comme telle, en teinte neutre.
class CourseTile extends StatelessWidget {
  const CourseTile({super.key, required this.course, this.highlighted = false});

  final Course course;

  /// Séance en cours : bordure accentuée.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color muted = scheme.onSurfaceVariant;
    final bool company = course.isCompanyPresence;
    final Color accent = company ? scheme.outline : subjectColor(course.subject);
    final String? teachers = company ? null : course.teachers;
    final String? group = course.group;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: highlighted
            ? BorderSide(color: scheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: accent),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 4, 16),
              child: SizedBox(
                width: 52,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormatFr.time(course.start),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      DateFormatFr.time(course.end),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company ? 'Présence en entreprise' : course.subject,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    if (company)
                      const _IconLine(icon: Icons.business_center_outlined, text: 'En entreprise')
                    else ...[
                      _IconLine(icon: Icons.person_outline_rounded, text: teachers ?? '—'),
                      _IconLine(icon: Icons.place_outlined, text: course.room ?? '—'),
                    ],
                    if (group != null) _IconLine(icon: Icons.groups_outlined, text: group),
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

class _IconLine extends StatelessWidget {
  const _IconLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
          ),
        ],
      ),
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
