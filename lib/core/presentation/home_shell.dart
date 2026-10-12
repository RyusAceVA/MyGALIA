import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/lifecycle/app_lifecycle_watcher.dart';
import 'package:mygalia/core/presentation/home_tabs.dart';
import 'package:mygalia/core/presentation/widgets/floating_pill_nav_bar.dart';
import 'package:mygalia/features/grades/presentation/grades_screen.dart';
import 'package:mygalia/features/home/presentation/home_screen.dart';
import 'package:mygalia/features/schedule/presentation/schedule_screen.dart';
import 'package:mygalia/features/settings/presentation/settings_screen.dart';

/// Écran principal : quatre onglets et barre de navigation flottante.
///
/// Les onglets restent en mémoire (pile indexée) : changer d'onglet ne
/// recharge rien et conserve la position de défilement ; le nouvel onglet
/// apparaît en fondu. Le bouton retour d'Android ramène d'abord à
/// l'accueil.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  static const List<PillNavItem> _items = [
    PillNavItem(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
      label: 'Accueil',
    ),
    PillNavItem(
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month_rounded,
      label: 'Planning',
    ),
    PillNavItem(
      icon: Icons.school_outlined,
      selectedIcon: Icons.school_rounded,
      label: 'Notes',
    ),
    PillNavItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      label: 'Paramètres',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HomeTab tab = ref.watch(homeTabProvider);
    void select(HomeTab next) => ref.read(homeTabProvider.notifier).state = next;

    // Retour du réseau / au premier plan : signaux de rechargement.
    return AppLifecycleWatcher(
      child: PopScope(
        canPop: tab == HomeTab.home,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (!didPop) select(HomeTab.home);
        },
        child: Scaffold(
          // Le contenu défile sous la barre flottante.
          extendBody: true,
          body: _TabStack(
            index: tab.index,
            children: const [
              HomeScreen(),
              ScheduleScreen(),
              GradesScreen(),
              SettingsScreen(),
            ],
          ),
          bottomNavigationBar: FloatingPillNavBar(
            items: _items,
            selectedIndex: tab.index,
            onSelected: (int index) => select(HomeTab.values[index]),
          ),
        ),
      ),
    );
  }
}

/// Pile d'onglets : seul l'onglet actif est affiché et animé ; les autres
/// restent en mémoire, animations suspendues.
class _TabStack extends StatelessWidget {
  const _TabStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: index,
      children: [
        for (int i = 0; i < children.length; i++)
          _TabFadeIn(
            active: i == index,
            child: TickerMode(enabled: i == index, child: children[i]),
          ),
      ],
    );
  }
}

class _TabFadeIn extends StatefulWidget {
  const _TabFadeIn({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_TabFadeIn> createState() => _TabFadeInState();
}

class _TabFadeInState extends State<_TabFadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.active ? 1 : 0,
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  late final Animation<Offset> _slide =
      Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(_curve);

  @override
  void didUpdateWidget(covariant _TabFadeIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
