import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/features/notifications/domain/notification_state.dart';

/// Familles de notifications (un canal Android chacune, réglable séparément
/// dans les paramètres du téléphone).
enum NotificationKind {
  newGrades(1001, 'notes', 'Nouvelles notes', 'Une note vient d\'être publiée.'),
  fridayReminder(
    1002,
    'rappels',
    'Rappel des cours',
    'Le vendredi : cours à l\'école la semaine suivante.',
  );

  const NotificationKind(this.id, this.channelId, this.channelName, this.channelDescription);

  final int id;
  final String channelId;
  final String channelName;
  final String channelDescription;
}

/// Affichage des notifications (surchargé dans les tests).
abstract interface class NotificationGateway {
  /// Demande l'autorisation d'afficher des notifications (Android 13+).
  /// Vrai si elles sont autorisées.
  Future<bool> requestPermission();

  Future<void> show(NotificationKind kind, NotificationText text);
}

/// Implémentation Android : `flutter_local_notifications`.
class LocalNotificationGateway implements NotificationGateway {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;

  Future<void> _init() => _ready ??= _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_mygalia'),
        ),
      );

  @override
  Future<bool> requestPermission() async {
    try {
      await _init();
      final AndroidFlutterLocalNotificationsPlugin? android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return false;
      return await android.requestNotificationsPermission() ?? false;
    } on Object catch (e) {
      AppLog.error('notifications : autorisation impossible (${e.runtimeType})');
      return false;
    }
  }

  @override
  Future<void> show(NotificationKind kind, NotificationText text) async {
    try {
      await _init();
      await _plugin.show(
        id: kind.id,
        title: text.title,
        body: text.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            kind.channelId,
            kind.channelName,
            channelDescription: kind.channelDescription,
            styleInformation: BigTextStyleInformation(text.body),
          ),
        ),
      );
    } on Object catch (e) {
      AppLog.error('notifications : affichage impossible (${e.runtimeType})');
    }
  }
}

final notificationGatewayProvider = Provider<NotificationGateway>((ref) {
  return LocalNotificationGateway();
});

/// Planification de la vérification en arrière-plan (surchargée en test).
abstract interface class BackgroundScheduler {
  /// Programme (ou reprogramme) la vérification périodique.
  Future<void> enable();

  /// Annule toute vérification.
  Future<void> disable();
}

/// Implémentation Android : WorkManager.
///
/// Une vérification toutes les [frequency], seulement avec du réseau. C'est
/// le système qui choisit l'instant exact (économie de batterie) : une note
/// est annoncée dans les heures qui suivent, pas à la minute.
class WorkmanagerScheduler implements BackgroundScheduler {
  static const String uniqueName = 'mygalia.verification';
  static const String taskName = 'verification';

  /// Quatre vérifications par jour au plus : le serveur de l'école n'est
  /// pas sollicité davantage que par un usage normal de l'app.
  static const Duration frequency = Duration(hours: 6);

  @override
  Future<void> enable() async {
    try {
      await Workmanager().registerPeriodicTask(
        uniqueName,
        taskName,
        frequency: frequency,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
      AppLog.lifecycle('vérification en arrière-plan programmée');
    } on Object catch (e) {
      AppLog.error('arrière-plan : programmation impossible (${e.runtimeType})');
    }
  }

  @override
  Future<void> disable() async {
    try {
      await Workmanager().cancelByUniqueName(uniqueName);
      AppLog.lifecycle('vérification en arrière-plan annulée');
    } on Object catch (e) {
      AppLog.error('arrière-plan : annulation impossible (${e.runtimeType})');
    }
  }
}

final backgroundSchedulerProvider = Provider<BackgroundScheduler>((ref) {
  return WorkmanagerScheduler();
});
