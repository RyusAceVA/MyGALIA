import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/debug/app_log.dart';

/// Raison d'un rechargement automatique.
enum RefreshReason {
  networkBack('retour du réseau'),
  resumed('retour au premier plan');

  const RefreshReason(this.label);

  final String label;
}

/// Bus des signaux de rechargement automatique. Chaque écran de données
/// décide seul s'il recharge (voir `DataLoader`) : seulement si son dernier
/// essai a échoué ou si ses données sont anciennes.
class RefreshSignals {
  final StreamController<RefreshReason> _controller =
      StreamController<RefreshReason>.broadcast();

  Stream<RefreshReason> get stream => _controller.stream;

  void emit(RefreshReason reason) {
    AppLog.lifecycle('signal : ${reason.label}');
    if (!_controller.isClosed) _controller.add(reason);
  }

  void dispose() {
    _controller.close();
  }
}

final refreshSignalsProvider = Provider<RefreshSignals>((ref) {
  final RefreshSignals signals = RefreshSignals();
  ref.onDispose(signals.dispose);
  return signals;
});
