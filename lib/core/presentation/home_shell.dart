import 'package:flutter/material.dart';

import 'package:mygalia/core/lifecycle/app_lifecycle_watcher.dart';
import 'package:mygalia/core/presentation/widgets/account_menu_button.dart';
import 'package:mygalia/features/grades/presentation/grades_screen.dart';
import 'package:mygalia/features/schedule/presentation/schedule_screen.dart';

/// Coquille principale : emploi du temps et notes.
///
/// Un onglet n'est construit (et ne charge ses données) qu'à sa première
/// ouverture, puis il reste en mémoire : pas de requêtes inutiles vers le
/// serveur de l'école.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final Set<int> _visited = <int>{0};

  @override
  Widget build(BuildContext context) {
    // Retour du réseau / au premier plan : signaux de rechargement.
    return AppLifecycleWatcher(
      child: _buildShell(),
    );
  }

  Widget _buildShell() {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const ScheduleScreen(actions: [AccountMenuButton()]),
          if (_visited.contains(1))
            const GradesScreen(actions: [AccountMenuButton()])
          else
            const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int index) => setState(() {
          _index = index;
          _visited.add(index);
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Emploi du temps',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: 'Notes',
          ),
        ],
      ),
    );
  }
}
