import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/lifecycle/network_status.dart';
import 'package:mygalia/core/lifecycle/refresh_signals.dart';

/// Source de l'état réseau (remplacée dans les tests : pas de plugin natif).
final connectivityProvider = Provider<Connectivity>((ref) => Connectivity());

/// Émet les signaux de rechargement : retour au premier plan, retour du
/// réseau. Monté avec l'écran principal (utilisateur connecté).
class AppLifecycleWatcher extends ConsumerStatefulWidget {
  const AppLifecycleWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLifecycleWatcher> createState() => _AppLifecycleWatcherState();
}

class _AppLifecycleWatcherState extends ConsumerState<AppLifecycleWatcher> {
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool? _online;

  @override
  void initState() {
    super.initState();
    final RefreshSignals signals = ref.read(refreshSignalsProvider);
    _lifecycle = AppLifecycleListener(
      onResume: () => signals.emit(RefreshReason.resumed),
    );
    final Connectivity connectivity = ref.read(connectivityProvider);
    _connectivitySub = connectivity.onConnectivityChanged.listen(
      _onConnectivity,
      onError: (Object error) =>
          AppLog.error('connectivité indisponible (${error.runtimeType})'),
    );
    connectivity.checkConnectivity().then(
          _onConnectivity,
          onError: (Object error) =>
              AppLog.error('connectivité indisponible (${error.runtimeType})'),
        );
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    if (!mounted) return;
    // Liste vide = état inconnu : on suppose le réseau disponible.
    final bool online = results.isEmpty ||
        results.any((ConnectivityResult r) => r != ConnectivityResult.none);
    final bool? wasOnline = _online;
    _online = online;
    ref.read(networkOnlineProvider.notifier).state = online;
    if (wasOnline == online) return;
    AppLog.lifecycle(online ? 'réseau disponible' : 'réseau perdu');
    if (wasOnline == false && online) {
      ref.read(refreshSignalsProvider).emit(RefreshReason.networkBack);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
