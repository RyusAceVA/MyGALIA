import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/features/notifications/data/notification_gateway.dart';
import 'package:mygalia/features/notifications/data/notification_store.dart';
import 'package:mygalia/features/notifications/domain/notification_state.dart';

final notificationSettingsProvider =
    AsyncNotifierProvider<NotificationSettingsController, NotificationState>(
  NotificationSettingsController.new,
);

/// Interrupteurs « Nouvelles notes » et « Rappel du vendredi ».
///
/// Activer demande l'autorisation Android puis programme la vérification en
/// arrière-plan ; tout couper l'annule.
class NotificationSettingsController extends AsyncNotifier<NotificationState> {
  @override
  Future<NotificationState> build() => ref.watch(notificationStoreProvider).read();

  /// Renvoie faux si l'autorisation a été refusée (rien n'est alors activé).
  Future<bool> setNewGrades(bool enabled) => _set(
        enabled,
        (NotificationState s) => s.copyWith(newGrades: enabled),
      );

  Future<bool> setFridayReminder(bool enabled) => _set(
        enabled,
        (NotificationState s) => s.copyWith(fridayReminder: enabled),
      );

  Future<bool> _set(
    bool enabled,
    NotificationState Function(NotificationState) change,
  ) async {
    if (enabled && !await ref.read(notificationGatewayProvider).requestPermission()) {
      return false;
    }
    final NotificationState next =
        await ref.read(notificationStoreProvider).update(change);
    state = AsyncData<NotificationState>(next);
    final BackgroundScheduler scheduler = ref.read(backgroundSchedulerProvider);
    await (next.anyEnabled ? scheduler.enable() : scheduler.disable());
    return true;
  }
}
