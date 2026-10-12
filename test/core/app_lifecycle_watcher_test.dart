import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/lifecycle/app_lifecycle_watcher.dart';
import 'package:mygalia/core/lifecycle/network_status.dart';
import 'package:mygalia/core/lifecycle/refresh_signals.dart';

import '../support/fake_connectivity.dart';

void main() {
  testWidgets('réseau perdu puis revenu : état hors ligne puis signal de rechargement', (tester) async {
    final FakeConnectivity connectivity = FakeConnectivity();
    final ProviderContainer container = ProviderContainer(
      overrides: [connectivityProvider.overrideWithValue(connectivity)],
    );
    addTearDown(container.dispose);
    final List<RefreshReason> signals = <RefreshReason>[];
    final sub = container.read(refreshSignalsProvider).stream.listen(signals.add);
    addTearDown(sub.cancel);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AppLifecycleWatcher(child: SizedBox()),
      ),
    );
    await tester.pump();
    expect(container.read(networkOnlineProvider), isTrue);

    connectivity.emit([ConnectivityResult.none]);
    await tester.pump();
    expect(container.read(networkOnlineProvider), isFalse);
    expect(signals, isEmpty);

    connectivity.emit([ConnectivityResult.mobile]);
    await tester.pump();
    expect(container.read(networkOnlineProvider), isTrue);
    expect(signals, [RefreshReason.networkBack]);

    // Wi-Fi en plus du mobile : toujours en ligne, pas de nouveau signal.
    connectivity.emit([ConnectivityResult.mobile, ConnectivityResult.wifi]);
    await tester.pump();
    expect(signals, hasLength(1));
  });

  testWidgets('retour au premier plan : signal de rechargement', (tester) async {
    final ProviderContainer container = ProviderContainer(
      overrides: [connectivityProvider.overrideWithValue(FakeConnectivity())],
    );
    addTearDown(container.dispose);
    final List<RefreshReason> signals = <RefreshReason>[];
    final sub = container.read(refreshSignalsProvider).stream.listen(signals.add);
    addTearDown(sub.cancel);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AppLifecycleWatcher(child: SizedBox()),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(signals, [RefreshReason.resumed]);
  });
}
