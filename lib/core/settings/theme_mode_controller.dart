import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'package:mygalia/core/constants/app_constants.dart';

/// Boîte Hive des préférences (`null` si elle n'est pas ouverte, ex. tests).
final settingsBoxProvider = Provider<Box<dynamic>?>((ref) {
  try {
    return Hive.box<dynamic>(AppConstants.settingsBox);
  } on Object {
    return null;
  }
});

/// Thème choisi par l'utilisateur (Clair / Sombre / Auto), mémorisé.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  static const String _key = 'theme_mode';

  @override
  ThemeMode build() {
    final Object? stored = ref.watch(settingsBoxProvider)?.get(_key);
    return ThemeMode.values
            .where((ThemeMode mode) => mode.name == stored)
            .firstOrNull ??
        ThemeMode.system;
  }

  Future<void> select(ThemeMode mode) async {
    state = mode;
    try {
      await ref.read(settingsBoxProvider)?.put(_key, mode.name);
    } on Object {
      // Préférence non mémorisée : le choix reste valable jusqu'au redémarrage.
    }
  }
}
