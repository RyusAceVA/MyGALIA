import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/debug/app_log.dart';

/// Lecture de la couleur d'accent du système (surchargée dans les tests).
abstract interface class SystemAccentSource {
  /// Couleur tirée du fond d'écran (Android 12+), ou `null` si le système
  /// n'en fournit pas.
  Future<Color?> read();
}

/// Implémentation Android : canal vers `MainActivity`.
class ChannelSystemAccentSource implements SystemAccentSource {
  const ChannelSystemAccentSource();

  static const MethodChannel _channel = MethodChannel('mygalia/theme');

  @override
  Future<Color?> read() async {
    try {
      final int? argb = await _channel.invokeMethod<int>('systemAccent');
      // Android renvoie un entier signé sur 32 bits.
      return argb == null ? null : Color(argb & 0xFFFFFFFF);
    } on Object catch (e) {
      AppLog.error('thème : couleur du système illisible (${e.runtimeType})');
      return null;
    }
  }
}

final systemAccentSourceProvider = Provider<SystemAccentSource>((ref) {
  return const ChannelSystemAccentSource();
});

/// Couleur d'accent du système, `null` tant qu'elle n'est pas connue ou si
/// le téléphone n'en fournit pas : l'app utilise alors sa couleur par défaut.
final systemAccentProvider = NotifierProvider<SystemAccentController, Color?>(
  SystemAccentController.new,
);

class SystemAccentController extends Notifier<Color?> {
  bool _disposed = false;

  @override
  Color? build() {
    ref.onDispose(() => _disposed = true);
    refresh();
    return null;
  }

  /// Relit la couleur : au démarrage, puis à chaque retour dans l'app (le
  /// fond d'écran a pu changer entre-temps).
  Future<void> refresh() async {
    final Color? color = await ref.read(systemAccentSourceProvider).read();
    if (!_disposed && color != state) state = color;
  }
}
