import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/constants/app_constants.dart';
import 'package:mygalia/core/debug/debug_tools_screen.dart';
import 'package:mygalia/core/presentation/expressive/material_shapes.dart';
import 'package:mygalia/core/presentation/expressive/shape_badge.dart';
import 'package:mygalia/core/presentation/widgets/profile_shape.dart';
import 'package:mygalia/core/presentation/widgets/section_title.dart';
import 'package:mygalia/core/settings/theme_mode_controller.dart';
import 'package:mygalia/core/storage/cache_store.dart';
import 'package:mygalia/features/auth/presentation/auth_controller.dart';
import 'package:mygalia/features/auth/presentation/sign_out_dialog.dart';
import 'package:mygalia/features/grades/presentation/grades_controller.dart';
import 'package:mygalia/features/notifications/domain/notification_state.dart';
import 'package:mygalia/features/notifications/presentation/notification_settings_controller.dart';
import 'package:mygalia/features/schedule/presentation/schedule_controller.dart';

/// Paramètres : profil, apparence, données (cache, déconnexion).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AuthState auth = ref.watch(authControllerProvider);
    final String email = auth is AuthSignedIn ? auth.email : '';
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    final Color danger = theme.colorScheme.error;

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          const SectionTitle('Profil'),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: ProfileShape(email: email, size: 52),
              title: const Text('Étudiant SC-Form'),
              subtitle: Text(email),
            ),
          ),
          const SizedBox(height: 16),
          const SectionTitle('Apparence'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _SettingShape(
                        shape: MaterialShapes.sunny,
                        icon: Icons.palette_outlined,
                        fill: theme.colorScheme.tertiaryContainer,
                        ink: theme.colorScheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Thème de l\'application',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      // Icônes seulement s'il y a la place : sur un écran
                      // étroit, « Sombre » passerait à la ligne.
                      final double textScale =
                          MediaQuery.textScalerOf(context).scale(14) / 14;
                      final bool icons = constraints.maxWidth >= 320 * textScale;
                      return SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ThemeMode>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.light,
                              icon: icons ? const Icon(Icons.light_mode_outlined) : null,
                              label: const Text('Clair'),
                            ),
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.dark,
                              icon: icons ? const Icon(Icons.dark_mode_outlined) : null,
                              label: const Text('Sombre'),
                            ),
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.system,
                              icon: icons ? const Icon(Icons.brightness_auto_outlined) : null,
                              label: const Text('Auto'),
                            ),
                          ],
                          selected: {themeMode},
                          onSelectionChanged: (Set<ThemeMode> selection) => ref
                              .read(themeModeProvider.notifier)
                              .select(selection.first),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const SectionTitle('Notifications'),
          const _NotificationCard(),
          const SizedBox(height: 16),
          const SectionTitle('Données'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: _SettingShape(
                    shape: MaterialShapes.clover4,
                    icon: Icons.cleaning_services_outlined,
                    fill: theme.colorScheme.secondaryContainer,
                    ink: theme.colorScheme.onSecondaryContainer,
                  ),
                  title: const Text('Vider le cache local'),
                  subtitle: const Text('Planning et notes enregistrés'),
                  onTap: () => _clearCache(context, ref),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  leading: _SettingShape(
                    shape: MaterialShapes.cookie4,
                    icon: Icons.logout_rounded,
                    fill: theme.colorScheme.errorContainer,
                    ink: theme.colorScheme.onErrorContainer,
                  ),
                  title: Text('Se déconnecter', style: TextStyle(color: danger)),
                  onTap: () => confirmSignOut(context, ref),
                ),
              ],
            ),
          ),
          // Constante à la compilation : absent (et retiré) en release.
          if (kDebugMode) ...[
            const SizedBox(height: 16),
            const SectionTitle('Diagnostic'),
            Card(
              child: ListTile(
                leading: _SettingShape(
                  shape: MaterialShapes.gem,
                  icon: Icons.bug_report_outlined,
                  fill: theme.colorScheme.tertiaryContainer,
                  ink: theme.colorScheme.onTertiaryContainer,
                ),
                title: const Text('Diagnostic (debug)'),
                subtitle: const Text('Journal, invalider la session'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const DebugToolsScreen()),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            '${AppConstants.appName} · client non officiel de SC Form',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    await ref.read(cacheStoreProvider).clear();
    // Les écrans déjà ouverts repartent du serveur, pas de leur mémoire.
    ref
      ..invalidate(scheduleControllerProvider)
      ..invalidate(gradesControllerProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cache local vidé.')),
    );
  }
}

/// Interrupteurs des notifications. Vérification en arrière-plan quelques
/// fois par jour : une note est annoncée dans les heures qui suivent.
class _NotificationCard extends ConsumerWidget {
  const _NotificationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final NotificationState state =
        ref.watch(notificationSettingsProvider).valueOrNull ?? const NotificationState();
    final NotificationSettingsController controller =
        ref.read(notificationSettingsProvider.notifier);

    Future<void> change(Future<bool> Function() apply) async {
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      if (await apply()) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Notifications refusées. Autorisez-les pour MyGalia dans les '
              'réglages Android.',
            ),
          ),
        );
    }

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: _SettingShape(
              shape: MaterialShapes.cookie9,
              icon: Icons.school_outlined,
              fill: theme.colorScheme.primaryContainer,
              ink: theme.colorScheme.onPrimaryContainer,
            ),
            title: const Text('Nouvelles notes'),
            subtitle: const Text('Prévenir quand une note est publiée'),
            value: state.newGrades,
            onChanged: (bool value) => change(() => controller.setNewGrades(value)),
          ),
          const Divider(indent: 16, endIndent: 16),
          SwitchListTile(
            secondary: _SettingShape(
              shape: MaterialShapes.pentagon,
              icon: Icons.event_repeat_outlined,
              fill: theme.colorScheme.secondaryContainer,
              ink: theme.colorScheme.onSecondaryContainer,
            ),
            title: const Text('Rappel du vendredi'),
            subtitle: const Text("Cours à l'école la semaine suivante"),
            value: state.fridayReminder,
            onChanged: (bool value) => change(() => controller.setFridayReminder(value)),
          ),
        ],
      ),
    );
  }
}

/// Icône de réglage dans une petite forme Material 3 Expressive.
class _SettingShape extends StatelessWidget {
  const _SettingShape({
    required this.shape,
    required this.icon,
    required this.fill,
    required this.ink,
  });

  final MaterialShape shape;
  final IconData icon;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) => ShapeBadge(
        shape: shape,
        size: 40,
        color: fill,
        child: Icon(icon, size: 20, color: ink),
      );
}
