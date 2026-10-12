import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dernier état réseau connu, tenu à jour par `AppLifecycleWatcher`.
///
/// Vrai par défaut : faute d'information, on ne bloque jamais une requête.
/// Hors ligne, les erreurs transitoires ne sont pas relancées (inutile) : le
/// rechargement se fait au retour du réseau.
final networkOnlineProvider = StateProvider<bool>((ref) => true);
