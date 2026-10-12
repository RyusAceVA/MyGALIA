import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/presentation/widgets/floating_pill_nav_bar.dart';

const List<PillNavItem> _items = [
  PillNavItem(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard_rounded, label: 'Accueil'),
  PillNavItem(icon: Icons.calendar_month_outlined, selectedIcon: Icons.calendar_month_rounded, label: 'Planning'),
  PillNavItem(icon: Icons.school_outlined, selectedIcon: Icons.school_rounded, label: 'Notes'),
  PillNavItem(icon: Icons.settings_outlined, selectedIcon: Icons.settings_rounded, label: 'Paramètres'),
];

/// Barre seule, dans un Scaffold, sur un écran de téléphone étroit (360 dp).
class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int selected = 0;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          extendBody: true,
          body: const SizedBox.expand(),
          bottomNavigationBar: FloatingPillNavBar(
            items: _items,
            selectedIndex: selected,
            onSelected: (int i) => setState(() => selected = i),
          ),
        ),
      );
}

void main() {
  setUp(() {
    final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.reset();
  });

  testWidgets('seul l\'onglet sélectionné affiche son titre', (tester) async {
    await tester.pumpWidget(const _Harness());

    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('Planning'), findsNothing);
    expect(find.text('Notes'), findsNothing);
    expect(find.text('Paramètres'), findsNothing);
    expect(find.byIcon(Icons.dashboard_rounded), findsOneWidget, reason: 'icône pleine');
  });

  testWidgets('toucher un onglet : il s\'élargit avec son titre, l\'ancien se replie', (tester) async {
    await tester.pumpWidget(const _Harness());

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Paramètres'), findsOneWidget);
    expect(find.text('Accueil'), findsNothing);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    expect(find.byIcon(Icons.dashboard_outlined), findsOneWidget);
  });

  testWidgets('la barre reste compacte (pas de débordement, hauteur raisonnable)', (tester) async {
    await tester.pumpWidget(const _Harness());
    for (final IconData icon in [
      Icons.calendar_month_outlined,
      Icons.school_outlined,
      Icons.settings_outlined,
    ]) {
      await tester.tap(find.byIcon(icon));
      await tester.pumpAndSettle();
    }

    final Size size = tester.getSize(find.byType(FloatingPillNavBar));
    expect(size.height, lessThan(120));
    expect(tester.takeException(), isNull);
  });

  testWidgets('les titres masqués restent annoncés aux lecteurs d\'écran', (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(const _Harness());

    expect(find.bySemanticsLabel('Planning'), findsOneWidget);
    expect(find.bySemanticsLabel('Paramètres'), findsOneWidget);
    semantics.dispose();
  });
}
