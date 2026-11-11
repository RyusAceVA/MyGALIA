import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:mygalia/core/storage/cache_store.dart';

import 'package:mygalia/features/auth/presentation/auth_controller.dart';
import 'package:mygalia/features/grades/data/grades_remote_data_source.dart';
import 'package:mygalia/features/notifications/data/notification_checker.dart';
import 'package:mygalia/features/notifications/data/notification_gateway.dart';
import 'package:mygalia/features/notifications/data/notification_store.dart';
import 'package:mygalia/features/notifications/domain/notification_state.dart';
import 'package:mygalia/features/notifications/presentation/notification_settings_controller.dart';
import 'package:mygalia/features/schedule/data/schedule_remote_data_source.dart';

import '../support/fake_notifications.dart';
import '../support/hive_test_utils.dart';
import '../support/test_env.dart';

void main() {
  late TestEnv env;
  late FakeNotificationGateway gateway;
  late FakeBackgroundScheduler scheduler;
  late NotificationStore store;
  late Box<dynamic> box;
  DateTime now = DateTime(2026, 11, 11, 10); // un mercredi

  NotificationChecker checker() => NotificationChecker(
        store: store,
        vault: env.vault,
        grades: env.container.read(gradesRemoteDataSourceProvider),
        schedule: env.container.read(scheduleRemoteDataSourceProvider),
        gateway: gateway,
        clock: () => now,
      );

  setUp(() async {
    now = DateTime(2026, 11, 11, 10);
    gateway = FakeNotificationGateway();
    scheduler = FakeBackgroundScheduler();
    box = await openTestBox();
    env = await TestEnv.start(
      overrides: [
        cacheStoreProvider.overrideWithValue(CacheStore(box)),
        notificationGatewayProvider.overrideWithValue(gateway),
        backgroundSchedulerProvider.overrideWithValue(scheduler),
      ],
    );
    await env.storeCredentials();
    env.server.twoClasses = true;
    store = env.container.read(notificationStoreProvider);
  });

  tearDown(() async {
    await env.dispose();
    await deleteTestBox(box);
  });

  test('tout coupé : aucune requête', () async {
    await checker().run();

    expect(env.server.loginCalls, 0);
    expect(gateway.shown, isEmpty);
  });

  test('déconnecté : aucune requête, aucune tentative de connexion', () async {
    await store.update((NotificationState s) => s.copyWith(newGrades: true));
    await env.vault.clearAll();
    await env.vault.saveNotificationState(
      const NotificationState(newGrades: true).toJson(),
    );

    await checker().run();

    expect(env.server.loginCalls, 0);
    expect(gateway.shown, isEmpty);
  });

  test('notes : point de départ silencieux, puis la nouvelle note est annoncée une fois',
      () async {
    await store.update((NotificationState s) => s.copyWith(newGrades: true));

    await checker().run();
    expect(gateway.shown, isEmpty, reason: 'les notes déjà là ne sont pas annoncées');
    expect(env.server.notesGetCalls, 1);

    env.server.extraGrade = true;
    await checker().run();
    expect(gateway.shown.single.$1, NotificationKind.newGrades);
    expect(gateway.shown.single.$2.body, 'Sécurité : 16/20');

    await checker().run();
    expect(gateway.shown, hasLength(1), reason: 'jamais annoncée deux fois');
  });

  test('note déjà vue dans l\'app : pas de notification', () async {
    await store.update((NotificationState s) => s.copyWith(newGrades: true));
    await checker().run();
    env.server.extraGrade = true;

    final snapshot = await env.container.read(gradesRemoteDataSourceProvider).fetch();
    await store.markSeen(snapshot.grades);
    await checker().run();

    expect(gateway.shown, isEmpty);
  });

  test('serveur en panne : aucune notification, rien de cassé, reprise ensuite',
      () async {
    await store.update((NotificationState s) => s.copyWith(newGrades: true));
    await checker().run();
    env.server
      ..extraGrade = true
      ..expireSchoolSession()
      ..expireApiTokens()
      ..loginOverride = (503, '');

    await checker().run();
    expect(gateway.shown, isEmpty);
    expect(await env.vault.readCredentials(), isNotNull);

    env.server.loginOverride = null;
    await checker().run();
    expect(gateway.shown, hasLength(1));
  });

  test('rappel : rien en semaine, une seule fois à partir du vendredi midi', () async {
    await store.update((NotificationState s) => s.copyWith(fridayReminder: true));

    await checker().run();
    expect(env.server.planningCalls, 0, reason: 'mercredi : pas de requête');

    now = DateTime(2026, 11, 13, 14);
    await checker().run();
    expect(env.server.planningCalls, 5, reason: 'la semaine suivante, une fois');
    expect(gateway.shown.single.$1, NotificationKind.fridayReminder);
    expect(gateway.shown.single.$2.body, contains('5 jours de cours'));
    expect((await store.read()).remindedWeek, '2026-11-16');

    now = DateTime(2026, 11, 14, 9);
    await checker().run();
    expect(env.server.planningCalls, 5, reason: 'déjà traitée');
    expect(gateway.shown, hasLength(1));
  });

  test('rappel : planning indisponible le vendredi, rattrapé le samedi', () async {
    await store.update((NotificationState s) => s.copyWith(fridayReminder: true));
    now = DateTime(2026, 11, 13, 14);
    env.server.planningServerErrors = 10;

    await checker().run();
    expect(gateway.shown, isEmpty);
    expect((await store.read()).remindedWeek, isNull);

    env.server.planningServerErrors = 0;
    now = DateTime(2026, 11, 14, 9);
    await checker().run();
    expect(gateway.shown, hasLength(1));
  });

  group('réglages', () {
    test('activer : autorisation demandée, vérification programmée', () async {
      final NotificationSettingsController controller =
          env.container.read(notificationSettingsProvider.notifier);
      await env.container.read(notificationSettingsProvider.future);

      expect(await controller.setNewGrades(true), isTrue);

      expect(gateway.permissionRequests, 1);
      expect(scheduler.enabled, isTrue);
      expect((await store.read()).newGrades, isTrue);
    });

    test('autorisation refusée : rien d\'activé ni de programmé', () async {
      gateway.granted = false;
      final NotificationSettingsController controller =
          env.container.read(notificationSettingsProvider.notifier);
      await env.container.read(notificationSettingsProvider.future);

      expect(await controller.setFridayReminder(true), isFalse);

      expect(scheduler.enabled, isFalse);
      expect((await store.read()).anyEnabled, isFalse);
    });

    test('tout couper annule la vérification ; en garder une la maintient', () async {
      final NotificationSettingsController controller =
          env.container.read(notificationSettingsProvider.notifier);
      await env.container.read(notificationSettingsProvider.future);
      await controller.setNewGrades(true);
      await controller.setFridayReminder(true);

      await controller.setNewGrades(false);
      expect(scheduler.enabled, isTrue);

      await controller.setFridayReminder(false);
      expect(scheduler.enabled, isFalse);
    });

    test('déconnexion : vérification annulée, réglages et mémoire effacés', () async {
      final ProviderContainer container = env.container;
      await container.read(notificationSettingsProvider.future);
      await container.read(notificationSettingsProvider.notifier).setNewGrades(true);
      await checker().run();
      expect((await store.read()).knownGrades, isNotEmpty);

      await container.read(authControllerProvider.notifier).signOut();

      expect(scheduler.enabled, isFalse);
      final NotificationState after = await store.read();
      expect(after.anyEnabled, isFalse);
      expect(after.knownGrades, isEmpty);
    });
  });
}
