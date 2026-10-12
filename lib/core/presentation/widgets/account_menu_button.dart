import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/features/auth/presentation/auth_controller.dart';

enum _AccountAction { signOut }

/// Menu du compte (barre d'application) : déconnexion.
class AccountMenuButton extends ConsumerWidget {
  const AccountMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AuthState auth = ref.watch(authControllerProvider);
    return PopupMenuButton<_AccountAction>(
      tooltip: 'Compte',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (_AccountAction action) {
        switch (action) {
          case _AccountAction.signOut:
            _confirmSignOut(context, ref);
        }
      },
      itemBuilder: (BuildContext context) => [
        if (auth is AuthSignedIn)
          PopupMenuItem<_AccountAction>(enabled: false, child: Text(auth.email)),
        const PopupMenuItem<_AccountAction>(
          value: _AccountAction.signOut,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout_rounded),
            title: Text('Se déconnecter'),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
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
}
