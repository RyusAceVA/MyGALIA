import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/network/dio_client.dart';
import 'package:mygalia/core/network/retry_policy.dart';
import 'package:mygalia/core/network/scform_config.dart';
import 'package:mygalia/core/session/school_client.dart';
import 'package:mygalia/core/session/session_manager.dart';
import 'package:mygalia/core/storage/secure_storage_service.dart';

import 'fake_scform_server.dart';
import 'in_memory_secure_store.dart';

/// Conteneur Riverpod branché sur un [FakeScFormServer] local, avec un coffre
/// en mémoire et des relances sans délai.
class TestEnv {
  TestEnv._(this.server, this.store, this.container);

  final FakeScFormServer server;
  final InMemorySecureKeyValueStore store;
  final ProviderContainer container;

  static Future<TestEnv> start({
    Duration receiveTimeout = const Duration(seconds: 5),
    InMemorySecureKeyValueStore? store,
    FakeScFormServer? server,
    List<Override> overrides = const <Override>[],
  }) async {
    final FakeScFormServer fake = server ?? (FakeScFormServer());
    if (server == null) await fake.start();
    final InMemorySecureKeyValueStore memory =
        store ?? InMemorySecureKeyValueStore();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        scFormConfigProvider.overrideWithValue(fake.config),
        dioProvider.overrideWith((ref) {
          final Dio dio = createScFormDio(
            fake.config,
            connectTimeout: const Duration(seconds: 2),
            receiveTimeout: receiveTimeout,
          );
          ref.onDispose(dio.close);
          return dio;
        }),
        secureKeyValueStoreProvider.overrideWithValue(memory),
        retryPolicyProvider.overrideWithValue(
          const RetryPolicy(delays: [Duration.zero, Duration.zero]),
        ),
        ...overrides,
      ],
    );
    return TestEnv._(fake, memory, container);
  }

  SessionManager get sessions => container.read(sessionManagerProvider);
  SchoolClient get school => container.read(schoolClientProvider);
  SecureStorageService get vault => container.read(secureStorageServiceProvider);

  /// Simule un utilisateur déjà connecté (identifiants dans le coffre).
  Future<void> storeCredentials() => vault.saveCredentials(
        Credentials(email: server.email, password: server.password),
      );

  /// Ferme le conteneur ; le serveur reste ouvert si [keepServer].
  Future<void> dispose({bool keepServer = false}) async {
    container.dispose();
    if (!keepServer) await server.close();
  }
}
