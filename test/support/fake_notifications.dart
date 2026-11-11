import 'package:mygalia/features/notifications/data/notification_gateway.dart';
import 'package:mygalia/features/notifications/domain/notification_state.dart';

/// Notifications en mémoire (aucun canal de plateforme).
class FakeNotificationGateway implements NotificationGateway {
  bool granted = true;
  int permissionRequests = 0;
  final List<(NotificationKind, NotificationText)> shown =
      <(NotificationKind, NotificationText)>[];

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return granted;
  }

  @override
  Future<void> show(NotificationKind kind, NotificationText text) async {
    shown.add((kind, text));
  }
}

/// Planification en mémoire.
class FakeBackgroundScheduler implements BackgroundScheduler {
  bool enabled = false;

  @override
  Future<void> enable() async => enabled = true;

  @override
  Future<void> disable() async => enabled = false;
}
