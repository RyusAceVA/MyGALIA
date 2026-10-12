import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/app.dart';
import 'package:mygalia/core/storage/secure_storage_service.dart';

import 'support/in_memory_secure_store.dart';

void main() {
  testWidgets("L'app démarre sur l'écran de garde puis propose la connexion", (tester) async {
    // MyGaliaApp doit être monté sous un ProviderScope (racine Riverpod).
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureKeyValueStoreProvider.overrideWithValue(InMemorySecureKeyValueStore()),
        ],
        child: const MyGaliaApp(),
      ),
    );

    // L'écran de garde affiche le nom de l'app pendant la lecture du coffre.
    expect(find.text('MyGalia'), findsOneWidget);

    // Coffre vide : écran de connexion.
    await tester.pump();
    await tester.pump();
    expect(find.text('Se connecter'), findsOneWidget);
  });
}
