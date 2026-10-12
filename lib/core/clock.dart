import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Horloge de l'app (fixée dans les tests).
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Heure courante, mise à jour à chaque changement de minute (comptes à
/// rebours de l'accueil). Le minuteur est arrêté dès que plus rien ne
/// l'écoute.
final minuteTickProvider =
    NotifierProvider.autoDispose<MinuteTick, DateTime>(MinuteTick.new);

class MinuteTick extends AutoDisposeNotifier<DateTime> {
  Timer? _timer;

  @override
  DateTime build() {
    final DateTime Function() clock = ref.watch(clockProvider);
    ref.onDispose(() => _timer?.cancel());
    _schedule(clock);
    return clock();
  }

  void _schedule(DateTime Function() clock) {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: 60 - clock().second), () {
      state = clock();
      _schedule(clock);
    });
  }
}
