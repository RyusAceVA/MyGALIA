import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Onglets de l'écran principal.
enum HomeTab { home, schedule, grades, settings }

/// Onglet affiché. Détruit avec l'écran principal : chaque connexion
/// repart de l'accueil.
final homeTabProvider = StateProvider.autoDispose<HomeTab>((ref) => HomeTab.home);
