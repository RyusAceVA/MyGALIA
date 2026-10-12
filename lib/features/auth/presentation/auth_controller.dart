import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/session/session_manager.dart';
import 'package:mygalia/core/storage/cache_store.dart';
import 'package:mygalia/core/storage/secure_storage_service.dart';
import 'package:mygalia/features/auth/data/auth_repository.dart';

/// État de connexion de l'utilisateur.
sealed class AuthState {
  const AuthState();
}

/// Lecture du coffre au démarrage.
final class AuthRestoring extends AuthState {
  const AuthRestoring();
}

/// Déconnecté. [message] explique pourquoi (ex. identifiants refusés).
final class AuthSignedOut extends AuthState {
  const AuthSignedOut({this.message});

  final String? message;
}

final class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.email);

  final String email;
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// Connexion, déconnexion, et retour à l'écran de connexion quand SC Form
/// refuse les identifiants enregistrés (seul cas de déconnexion forcée).
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final StreamSubscription<Failure> lost = ref
        .watch(sessionManagerProvider)
        .sessionLost
        .listen((Failure failure) => signOut(message: failure.message));
    ref.onDispose(lost.cancel);
    _restore();
    return const AuthRestoring();
  }

  Future<void> _restore() async {
    final Credentials? credentials =
        await ref.read(secureStorageServiceProvider).readCredentials();
    if (state is! AuthRestoring) return; // Connexion ou déconnexion entre-temps.
    state = credentials == null
        ? const AuthSignedOut()
        : AuthSignedIn(credentials.email);
  }

  /// Connexion explicite. Renvoie l'erreur à afficher, ou `null` si succès.
  /// Des identifiants refusés ne sont jamais relancés automatiquement.
  Future<Failure?> signIn(String email, String password) async {
    final Credentials credentials =
        Credentials(email: email.trim(), password: password);
    try {
      final ApiToken token =
          await ref.read(authRepositoryProvider).login(credentials);
      // Repartir de zéro : aucune trace d'une session précédente.
      await _purge();
      final SecureStorageService storage = ref.read(secureStorageServiceProvider);
      await storage.saveCredentials(credentials);
      await storage.saveApiToken(token);
      AppLog.auth('connexion réussie');
      state = AuthSignedIn(credentials.email);
      return null;
    } on Failure catch (failure) {
      return failure;
    } on Object catch (error) {
      return UnknownFailure('Connexion impossible.', cause: error);
    }
  }

  /// Déconnexion (volontaire ou identifiants refusés).
  Future<void> signOut({String? message}) async {
    await _purge();
    // Le message du serveur n'est pas journalisé (il peut citer l'e-mail).
    AppLog.auth(message == null ? 'déconnexion' : 'déconnexion (session perdue)');
    state = AuthSignedOut(message: message);
  }

  /// Repart de zéro : rien d'une session précédente ne subsiste.
  ///  * session en mémoire et cookies oubliés : les opérations en cours ne
  ///    pourront plus rien enregistrer ;
  ///  * coffre vidé : identifiants, jeton API, session école (cookies,
  ///    segment, pkEntite) ;
  ///  * cache Hive vidé : planning et notes.
  /// Les écrans de données, détruits avec l'écran principal, annulent leurs
  /// requêtes en cours.
  Future<void> _purge() async {
    ref.read(sessionManagerProvider).reset();
    await ref.read(secureStorageServiceProvider).clearAll();
    await ref.read(cacheStoreProvider).clear();
  }
}
