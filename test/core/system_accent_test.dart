import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/theme/app_colors.dart';
import 'package:mygalia/core/theme/system_accent.dart';

class _FakeSource implements SystemAccentSource {
  Color? color;

  @override
  Future<Color?> read() async => color;
}

void main() {
  test('sans couleur du système : indigo par défaut', () {
    expect(AppColors.light().primary, AppColors.light(AppColors.seed).primary);
    expect(AppColors.dark().primary, AppColors.dark(AppColors.seed).primary);
  });

  test('la couleur du système change l\'accent, pas les fonds neutres', () {
    const Color green = Color(0xFF3A7D44);
    expect(AppColors.light(green).primary, isNot(AppColors.light().primary));
    expect(AppColors.dark(green).primary, isNot(AppColors.dark().primary));
    expect(AppColors.light(green).surface, AppColors.paperSurface);
    expect(AppColors.dark(green).surfaceContainerLowest, AppColors.inkBackground);
  });

  test('lue au démarrage, puis relue à la demande (fond d\'écran changé)', () async {
    final _FakeSource source = _FakeSource()..color = const Color(0xFF3A7D44);
    final ProviderContainer container = ProviderContainer(
      overrides: [systemAccentSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);

    expect(container.read(systemAccentProvider), isNull);
    await pumpEventQueue();
    expect(container.read(systemAccentProvider), const Color(0xFF3A7D44));

    source.color = const Color(0xFFB3261E);
    await container.read(systemAccentProvider.notifier).refresh();
    expect(container.read(systemAccentProvider), const Color(0xFFB3261E));

    source.color = null;
    await container.read(systemAccentProvider.notifier).refresh();
    expect(container.read(systemAccentProvider), isNull);
  });
}
