import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:mygalia/core/settings/theme_mode_controller.dart';
import 'package:mygalia/core/storage/secure_storage_service.dart';
import 'package:mygalia/features/settings/presentation/settings_screen.dart';

import '../support/hive_test_utils.dart';
import '../support/in_memory_secure_store.dart';

void main() {
  late Box<dynamic> box;

  setUp(() async {
    box = await openTestBox();
  });

  tearDown(() => deleteTestBox(box));

  test('thème : Auto par défaut, choix mémorisé et relu au démarrage', () async {
    final ProviderContainer first = ProviderContainer(
      overrides: [settingsBoxProvider.overrideWithValue(box)],
    );
    expect(first.read(themeModeProvider), ThemeMode.system);

    await first.read(themeModeProvider.notifier).select(ThemeMode.dark);
    first.dispose();

    final ProviderContainer restarted = ProviderContainer(
      overrides: [settingsBoxProvider.overrideWithValue(box)],
    );
    expect(restarted.read(themeModeProvider), ThemeMode.dark);
    restarted.dispose();
  });

  test('sans boîte de préférences : Auto, sans erreur', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: [settingsBoxProvider.overrideWithValue(null)],
    );

    expect(container.read(themeModeProvider), ThemeMode.system);
    await container.read(themeModeProvider.notifier).select(ThemeMode.light);
    expect(container.read(themeModeProvider), ThemeMode.light);
    container.dispose();
  });

  testWidgets('Paramètres : profil, thème, cache et déconnexion', (tester) async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        settingsBoxProvider.overrideWithValue(null),
        secureKeyValueStoreProvider.overrideWithValue(InMemorySecureKeyValueStore()),
      ],
    );
    addTearDown(container.dispose);
    // Écran haut : toutes les cartes (dont Notifications) sont construites.
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    expect(find.text('Étudiant SC-Form'), findsOneWidget);
    expect(find.text('Vider le cache local'), findsOneWidget);
    expect(find.text('Nouvelles notes'), findsOneWidget);
    expect(find.text('Rappel du vendredi'), findsOneWidget);
    expect(find.text('Se déconnecter'), findsOneWidget);

    await tester.tap(find.text('Sombre'));
    await tester.pump();
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });
}
