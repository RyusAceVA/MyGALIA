import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/storage/secure_storage_service.dart';
import 'package:mygalia/features/grades/domain/grade.dart';
import 'package:mygalia/features/notifications/domain/notification_state.dart';

/// Réglages et mémoire des notifications, dans le coffre : lisibles par
/// l'app comme par la tâche de fond (voir [NotificationState]).
class NotificationStore {
  NotificationStore(this._vault);

  final SecureStorageService _vault;

  /// État enregistré ; par défaut (tout coupé) s'il est absent ou illisible.
  Future<NotificationState> read() async {
    final Map<String, Object?>? json = await _vault.readNotificationState();
    if (json == null) return const NotificationState();
    try {
      return NotificationState.fromJson(json);
    } on Object {
      return const NotificationState();
    }
  }

  /// Lit, transforme, enregistre. Renvoie le nouvel état.
  Future<NotificationState> update(
    NotificationState Function(NotificationState current) change,
  ) async {
    final NotificationState next = change(await read());
    try {
      await _vault.saveNotificationState(next.toJson());
    } on CacheFailure {
      AppLog.error('notifications : état non enregistré (coffre indisponible)');
    }
    return next;
  }

  /// Notes vues dans l'app : elles ne seront pas annoncées ensuite.
  Future<void> markSeen(List<Grade> grades) async {
    final NotificationState current = await read();
    if (!current.newGrades) return;
    await update((NotificationState s) => checkGrades(s, grades).state);
  }
}

final notificationStoreProvider = Provider<NotificationStore>((ref) {
  return NotificationStore(ref.watch(secureStorageServiceProvider));
});
