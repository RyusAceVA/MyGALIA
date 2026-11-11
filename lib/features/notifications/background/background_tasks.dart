import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/features/notifications/data/notification_checker.dart';

/// Point d'entrée de la tâche de fond (WorkManager), lancé par le système
/// dans un isolat à part, app fermée ou non.
///
/// Renvoie toujours « réussi » : un échec est retenté à la vérification
/// périodique suivante, jamais en rafale par WorkManager.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? inputData) async {
    final ProviderContainer container = ProviderContainer();
    try {
      await container.read(notificationCheckerProvider).run();
    } on Object catch (error) {
      AppLog.error('arrière-plan : erreur inattendue (${error.runtimeType})');
    } finally {
      container.dispose();
    }
    return true;
  });
}

/// À appeler au démarrage de l'app : déclare le point d'entrée à WorkManager.
Future<void> initializeBackgroundTasks() async {
  try {
    await Workmanager().initialize(backgroundDispatcher);
  } on Object catch (error) {
    AppLog.error('arrière-plan : initialisation impossible (${error.runtimeType})');
  }
}
