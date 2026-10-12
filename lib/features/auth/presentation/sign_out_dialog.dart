import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/features/auth/presentation/auth_controller.dart';

/// Demande confirmation puis déconnecte (identifiants, session, cache).
Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text('Se déconnecter ?'),
      content: const Text(
        'Vos identifiants, la session et les données en cache seront '
        'effacés de cet appareil.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Se déconnecter'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) {
    await ref.read(authControllerProvider.notifier).signOut();
  }
}
