import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Connectivité pilotée par le test (aucun plugin natif en test).
class FakeConnectivity implements Connectivity {
  FakeConnectivity([this.initial = const [ConnectivityResult.wifi]]);

  final List<ConnectivityResult> initial;
  final StreamController<List<ConnectivityResult>> _changes =
      StreamController<List<ConnectivityResult>>.broadcast();

  void emit(List<ConnectivityResult> results) => _changes.add(results);

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => initial;
}
