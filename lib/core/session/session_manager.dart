import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/network/retry_policy.dart';
import 'package:mygalia/core/storage/secure_storage_service.dart';
import 'package:mygalia/features/auth/data/auth_repository.dart';
import 'package:mygalia/features/auth/data/edc_session_bootstrap.dart';
import 'package:mygalia/features/auth/domain/edc_session.dart';

/// Propriétaire unique de la session SC Form (jeton API + session école).
///
/// Garanties :
///  * **une seule reconnexion à la fois** (« single flight ») : les requêtes
///    qui échouent en même temps attendent la MÊME reconnexion, puis rejouent ;
///  * une reconnexion repart TOUJOURS d'une session propre : l'ancien cookie
///    jar, le segment `(S(…))` et le pkEntite sont jetés avant la poignée de
///    main, qui crée un jar neuf ;
///  * identifiants refusés (ou absents) → purge du coffre et événement
///    [sessionLost] (retour à l'écran de connexion). AUCUNE autre erreur ne
///    déconnecte l'utilisateur.
class SessionManager {
  SessionManager({
    required SecureStorageService storage,
    required AuthRepository auth,
    required EdcSessionBootstrap bootstrap,
    required RetryPolicy retry,
    DateTime Function()? clock,
  })  : _storage = storage,
        _auth = auth,
        _bootstrap = bootstrap,
        _retry = retry,
        _clock = clock ?? DateTime.now;

  final SecureStorageService _storage;
  final AuthRepository _auth;
  final EdcSessionBootstrap _bootstrap;
  final RetryPolicy _retry;
  final DateTime Function() _clock;

  final StreamController<Failure> _sessionLost =
      StreamController<Failure>.broadcast();

  EdcSession? _session;
  ApiToken? _apiToken;
  Future<void>? _restoring;
  Future<EdcSession>? _renewal;
  int _generation = 0;

  /// Incrémenté à chaque [reset] : une opération lancée avant une
  /// déconnexion ne peut plus enregistrer de session ensuite.
  int _epoch = 0;
  int _renewals = 0;

  /// Vrai après une déconnexion : aucune reconnexion jusqu'à la prochaine
  /// connexion (les chargements encore en vol sont simplement annulés).
  bool _signedOut = false;

  /// Émet quand l'utilisateur doit se reconnecter (identifiants refusés ou
  /// absents du coffre).
  Stream<Failure> get sessionLost => _sessionLost.stream;

  /// Change à chaque déconnexion ou connexion : un chargement qui le voit
  /// changer ne doit plus rien écrire (cache compris).
  int get epoch => _epoch;

  /// Nombre de reconnexions effectuées (tests, diagnostic).
  @visibleForTesting
  int get renewalCount => _renewals;

  /// Session école utilisable : mémoire, sinon coffre, sinon reconnexion.
  Future<EdcSession> current() async {
    if (_signedOut) throw const CancelledFailure();
    await (_restoring ??= _restore());
    final EdcSession? session = _session;
    if (session != null) return session;
    return renew();
  }

  /// Remplace la session de génération [staleGeneration], jugée invalide.
  ///
  /// Si une session plus récente existe déjà (une autre requête vient de la
  /// renouveler), elle est rendue sans nouvelle reconnexion. Si une
  /// reconnexion est en cours, son résultat est partagé.
  Future<EdcSession> renew({int? staleGeneration}) {
    if (_signedOut) {
      return Future<EdcSession>.error(const CancelledFailure());
    }
    final EdcSession? session = _session;
    if (session != null &&
        staleGeneration != null &&
        session.generation > staleGeneration) {
      AppLog.session(
        'session déjà renouvelée (génération ${session.generation}) : '
        'rejeu sans nouvelle reconnexion',
      );
      return Future<EdcSession>.value(session);
    }
    final Future<EdcSession>? inFlight = _renewal;
    if (inFlight != null) {
      AppLog.session('reconnexion déjà en cours : attente de son résultat');
      return inFlight;
    }
    final Future<EdcSession> renewal = _runRenewal(_epoch);
    _renewal = renewal;
    return renewal;
  }

  /// Persiste les cookies reçus en cours de route (ex. `ASP.NET_SessionId`
  /// de PlanningWeb), si [session] est toujours la session courante.
  Future<void> persistIfCurrent(EdcSession session) async {
    if (!identical(session, _session)) return;
    await _persist(session);
  }

  /// Oublie tout : les opérations en cours ne pourront plus rien enregistrer.
  ///  * [signedIn] faux (déconnexion) : plus aucune reconnexion jusqu'à la
  ///    prochaine connexion ; les chargements encore en vol sont annulés ;
  ///  * [signedIn] vrai (nouvelle connexion) : on repart de zéro.
  void reset({required bool signedIn}) {
    _epoch++;
    _signedOut = !signedIn;
    _session = null;
    _apiToken = null;
    _renewal = null;
    _restoring = null;
    AppLog.session(signedIn ? 'session réinitialisée (connexion)' : 'session fermée (déconnexion)');
  }

  void dispose() {
    _sessionLost.close();
  }

  /// Debug uniquement : rend la session courante invalide côté serveur
  /// (cookies et segment faussés), et si [alsoApiToken] le jeton API aussi.
  /// La requête suivante doit réparer la session toute seule.
  Future<bool> debugInvalidate({required bool alsoApiToken}) async {
    if (!kDebugMode) return false;
    await (_restoring ??= _restore());
    final EdcSession? session = _session;
    if (session != null) {
      final EdcSession corrupted = session.debugCorrupted();
      _session = corrupted;
      await _persist(corrupted);
    }
    if (alsoApiToken) {
      final ApiToken fake = ApiToken(
        'jeton-invalide-debug',
        expiresAt: _clock().add(const Duration(hours: 1)),
      );
      _apiToken = fake;
      try {
        await _storage.saveApiToken(fake);
      } on CacheFailure {
        AppLog.error('jeton API factice non persisté');
      }
    }
    AppLog.session(
      'DEBUG : session invalidée${alsoApiToken ? ' (jeton API compris)' : ''}'
      ' — la prochaine requête doit se réparer seule',
    );
    return session != null || alsoApiToken;
  }

  /// Debug uniquement : résumé lisible de la session, sans aucune valeur
  /// secrète (noms de cookies seulement).
  String debugSummary() {
    if (!kDebugMode) return '';
    final EdcSession? session = _session;
    final ApiToken? token = _apiToken;
    final String api = token == null
        ? 'jeton API : non chargé'
        : 'jeton API : expire ${token.expiresAt?.toLocal() ?? '(date inconnue)'}';
    if (session == null) {
      return 'Session école : aucune en mémoire · $api · '
          'reconnexions : $_renewals';
    }
    return 'Session école : génération ${session.generation}, ouverte le '
        '${session.createdAt.toLocal()} · cookies : '
        '${session.jar.names.join(', ')} · segment (S(…)) : '
        '${session.segment == null ? 'absent' : 'présent'} · pkEntite : '
        '${session.planningId == null ? 'absent' : 'présent'} · $api · '
        'reconnexions : $_renewals';
  }

  Future<void> _restore() async {
    final int epoch = _epoch;
    final Map<String, Object?>? json = await _storage.readEdcSession();
    if (json == null || epoch != _epoch || _session != null) return;
    final EdcSession? restored = EdcSession.tryFromJson(json);
    if (restored == null) {
      AppLog.session('session école stockée illisible : supprimée');
      await _storage.deleteEdcSession();
      return;
    }
    _session = restored;
    _generation = max(_generation, restored.generation);
    AppLog.session(
      'session école restaurée depuis le coffre '
      '(génération ${restored.generation})',
    );
  }

  Future<EdcSession> _runRenewal(int epoch) async {
    try {
      return await _renewOnce(epoch);
    } finally {
      // Une reconnexion terminée (succès ou échec) libère la place : rien ne
      // peut rester bloqué sur un ancien Future.
      if (epoch == _epoch) _renewal = null;
    }
  }

  Future<EdcSession> _renewOnce(int epoch) async {
    final int generation = ++_generation;
    _renewals++;
    AppLog.session('reconnexion silencieuse (génération $generation)…');

    // Repartir d'une session propre : l'ancienne n'est plus utilisable.
    _session = null;
    await _storage.deleteEdcSession();

    // L'époque est revérifiée avant chaque étape réseau ou stockage : une
    // reconnexion qui chevauche une déconnexion (puis éventuellement une
    // nouvelle connexion) s'arrête net, sans toucher aux données de la
    // nouvelle session ni envoyer l'ancien mot de passe.
    try {
      _ensureEpoch(epoch);
      final Credentials? credentials = await _storage.readCredentials();
      _ensureEpoch(epoch);
      if (credentials == null) throw const SignedOutFailure();

      ApiToken token = await _usableApiToken(credentials, epoch);
      EdcSession session;
      try {
        session = await _retry.run(
          'poignée de main EDC',
          () => _handshake(credentials, token, generation),
        );
      } on ApiTokenRejected catch (rejected) {
        _ensureEpoch(epoch);
        AppLog.session(
          'jeton API refusé (HTTP ${rejected.status}) : nouvelle connexion API',
        );
        _apiToken = null;
        await _storage.deleteApiToken();
        token = await _loginAndStore(credentials, epoch);
        try {
          session = await _retry.run(
            'poignée de main EDC',
            () => _handshake(credentials, token, generation),
          );
        } on ApiTokenRejected {
          throw const SessionFailure(
            'SC Form refuse le jeton de connexion qu\'il vient de délivrer. '
            'Réessayez plus tard.',
          );
        }
      }

      _ensureEpoch(epoch);
      _session = session;
      await _persist(session);
      AppLog.session('reconnexion réussie (génération $generation)');
      return session;
    } on InvalidCredentialsFailure catch (failure) {
      await _loseSession(epoch, failure);
      rethrow;
    } on SignedOutFailure catch (failure) {
      await _loseSession(epoch, failure);
      rethrow;
    }
  }

  Future<EdcSession> _handshake(
    Credentials credentials,
    ApiToken token,
    int generation,
  ) async {
    final String transition = await _auth.getEdcTransitionToken(
      email: credentials.email,
      token: token,
    );
    return _bootstrap.open(
      email: credentials.email,
      transitionToken: transition,
      generation: generation,
    );
  }

  Future<ApiToken> _usableApiToken(Credentials credentials, int epoch) async {
    final ApiToken? token = _apiToken ?? await _storage.readApiToken();
    _ensureEpoch(epoch);
    if (token != null && token.isUsable(_clock())) {
      _apiToken = token;
      return token;
    }
    AppLog.session(
      token == null ? 'aucun jeton API : connexion' : 'jeton API expiré : connexion',
    );
    return _loginAndStore(credentials, epoch);
  }

  Future<ApiToken> _loginAndStore(Credentials credentials, int epoch) async {
    // Jamais de connexion avec les identifiants d'une session close.
    _ensureEpoch(epoch);
    final ApiToken token = await _auth.login(credentials);
    _ensureEpoch(epoch);
    _apiToken = token;
    try {
      await _storage.saveApiToken(token);
    } on CacheFailure {
      AppLog.error('jeton API non persisté (coffre indisponible)');
    }
    return token;
  }

  Future<void> _persist(EdcSession session) async {
    try {
      await _storage.saveEdcSession(session.toJson());
    } on CacheFailure {
      // La session reste utilisable en mémoire.
      AppLog.error('session école non persistée (coffre indisponible)');
    }
  }

  Future<void> _loseSession(int epoch, Failure failure) async {
    if (epoch != _epoch) return;
    AppLog.auth(
      'reconnexion impossible (${failure.runtimeType}) : retour à l\'écran '
      'de connexion',
    );
    _apiToken = null;
    await _storage.clearAll();
    if (!_sessionLost.isClosed) _sessionLost.add(failure);
  }

  void _ensureEpoch(int epoch) {
    if (epoch != _epoch) throw const CancelledFailure();
  }
}

final sessionManagerProvider = Provider<SessionManager>((ref) {
  final SessionManager manager = SessionManager(
    storage: ref.watch(secureStorageServiceProvider),
    auth: ref.watch(authRepositoryProvider),
    bootstrap: ref.watch(edcSessionBootstrapProvider),
    retry: ref.watch(retryPolicyProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});
