import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/session/session_manager.dart';
import 'package:mygalia/core/storage/cache_store.dart';

/// Outils de diagnostic — **build debug uniquement**.
///
/// N'est accessible que depuis un menu construit sous `if (kDebugMode)` : en
/// release, le code est retiré à la compilation.
///  * « Invalider la session » simule une expiration côté serveur : la
///    requête suivante doit réparer la session toute seule ;
///  * le journal montre les étapes de session, codes HTTP, redirections et
///    décisions cache/réseau (secrets masqués).
class DebugToolsScreen extends ConsumerWidget {
  const DebugToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostic (debug)'),
        actions: const [
          IconButton(
            tooltip: 'Effacer le journal',
            icon: Icon(Icons.delete_sweep_outlined),
            onPressed: AppLog.clear,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: AppLog.revision,
                  builder: (BuildContext context, int _, Widget? __) => Text(
                    ref.read(sessionManagerProvider).debugSummary(),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => _invalidate(context, ref, alsoApiToken: false),
                  icon: const Icon(Icons.timer_off_outlined),
                  label: const Text('Invalider la session école'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _invalidate(context, ref, alsoApiToken: true),
                  icon: const Icon(Icons.key_off_outlined),
                  label: const Text('Invalider aussi le jeton API'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _clearCache(context, ref),
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Vider le cache local'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Après une invalidation, revenez à un écran et tirez-le vers '
                  'le bas : l\'app doit se reconnecter seule (voir le journal).',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: AppLog.revision,
              builder: (BuildContext context, int _, Widget? __) {
                final List<LogEntry> entries = AppLog.entries.reversed.toList();
                if (entries.isEmpty) {
                  return const Center(child: Text('Journal vide.'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: entries.length,
                  itemBuilder: (BuildContext context, int i) =>
                      _LogLine(entry: entries[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _invalidate(
    BuildContext context,
    WidgetRef ref, {
    required bool alsoApiToken,
  }) async {
    final bool done = await ref
        .read(sessionManagerProvider)
        .debugInvalidate(alsoApiToken: alsoApiToken);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          done
              ? 'Session invalidée. Tirez un écran vers le bas : l\'app doit '
                  'se réparer seule.'
              : 'Aucune session ouverte pour l\'instant.',
        ),
      ),
    );
  }

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    await ref.read(cacheStoreProvider).clear();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cache local vidé.')),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});

  final LogEntry entry;

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime t = entry.time;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)} ',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            TextSpan(
              text: '[${entry.category}] ',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: entry.message),
          ],
        ),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}
