import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/app.dart';

void main() {
  testWidgets('L\'app démarre et affiche l\'écran de garde', (tester) async {
    // MyGaliaApp doit être monté sous un ProviderScope (racine Riverpod).
    await tester.pumpWidget(const ProviderScope(child: MyGaliaApp()));

    // L'écran de garde affiche le nom de l'app.
    expect(find.text('MyGalia'), findsOneWidget);
  });
}
