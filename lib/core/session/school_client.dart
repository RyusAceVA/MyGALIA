import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/debug/redact.dart';
import 'package:mygalia/core/network/dio_client.dart';
import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/network/retry_policy.dart';
import 'package:mygalia/core/network/scform_config.dart';
import 'package:mygalia/core/session/session_manager.dart';
import 'package:mygalia/core/session/session_validator.dart';
import 'package:mygalia/features/auth/domain/edc_session.dart';

/// Signal interne : la réponse prouve que la session école n'est plus valide.
class _SessionRejected implements Exception {
  _SessionRejected(this.reason, {required this.afterReplay});

  final String reason;

  /// Erreur à remonter si la session est encore refusée après le rejeu.
  final Failure Function() afterReplay;
}

Failure _sessionLost() => const SessionFailure(
      'La session sur l\'espace école a expiré et n\'a pas pu être rétablie. '
      'Réessayez dans un instant.',
    );

/// Point d'entrée UNIQUE des requêtes vers l'instance école (planning, notes).
///
/// C'est ici, et seulement ici, qu'une session invalide est reconnue :
///  * redirection (3xx) : jamais attendue pour une page de données ;
///  * 401 / 403 ;
///  * page de connexion renvoyée en 200 ;
///  * page vide.
///
/// Dans tous ces cas, la session est renouvelée (une seule reconnexion pour
/// toutes les requêtes concernées, voir [SessionManager.renew]) puis
/// l'opération est rejouée UNE seule fois. Les erreurs transitoires (timeout,
/// 5xx, coupure) sont relancées par [RetryPolicy], requête par requête.
class SchoolClient {
  SchoolClient(this._dio, this._config, this._sessions, this._retry);

  final Dio _dio;
  final ScFormConfig _config;
  final SessionManager _sessions;
  final RetryPolicy _retry;

  /// Exécute [operation] avec une session valide (voir la doc de la classe).
  Future<T> run<T>(
    String label,
    Future<T> Function(SchoolRequester school) operation, {
    CancelToken? cancelToken,
  }) async {
    final EdcSession first = await _sessions.current();
    _throwIfCancelled(cancelToken);
    try {
      return await operation(SchoolRequester._(this, first, cancelToken));
    } on _SessionRejected catch (rejected) {
      AppLog.session(
        '$label : session refusée (${rejected.reason}) → reconnexion puis '
        'rejeu unique',
      );
      final EdcSession renewed =
          await _sessions.renew(staleGeneration: first.generation);
      _throwIfCancelled(cancelToken);
      try {
        final T result =
            await operation(SchoolRequester._(this, renewed, cancelToken));
        AppLog.session('$label : rejeu réussi');
        return result;
      } on _SessionRejected catch (again) {
        AppLog.session('$label : toujours refusée après rejeu (${again.reason})');
        throw again.afterReplay();
      }
    }
  }

  /// Corps `application/x-www-form-urlencoded`, encodé explicitement.
  static String encodeForm(Map<String, String> fields) => fields.entries
      .map((MapEntry<String, String> e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');

  Future<String> _fetch(
    SchoolRequester requester,
    String method,
    Uri uri, {
    Map<String, String>? form,
    Pattern? dataMarker,
  }) async {
    final EdcSession session = requester.session;
    final String? body = form == null ? null : encodeForm(form);

    final Response<String> response = await _retry.run(
      '$method ${Redact.uri(uri)}',
      () async {
        final String? cookie = session.jar.headerFor(uri);
        final Response<String> r;
        try {
          r = await _dio.requestUri<String>(
            uri,
            data: body,
            options: Options(
              method: method,
              contentType:
                  body == null ? null : Headers.formUrlEncodedContentType,
              headers: {if (cookie != null) 'Cookie': cookie},
            ),
            cancelToken: requester._cancelToken,
          );
        } on DioException catch (e) {
          throw failureFromDioException(e);
        }
        await _captureCookies(session, uri, r);
        final int status = r.statusCode ?? 0;
        if (status >= 500) throw ServerFailure.status(status);
        return r;
      },
      cancelToken: requester._cancelToken,
    );

    final int status = response.statusCode ?? 0;
    if (SessionValidator.isRedirect(status)) {
      final String? location = response.headers['location']?.firstOrNull;
      throw _SessionRejected(
        'redirection $status vers ${Redact.location(location, uri)}',
        afterReplay: _sessionLost,
      );
    }
    if (status == 401 || status == 403) {
      throw _SessionRejected('HTTP $status', afterReplay: _sessionLost);
    }
    if (status != 200) throw ServerFailure.status(status);

    final String data = response.data ?? '';
    if (data.trim().isEmpty) {
      throw _SessionRejected(
        'page vide',
        afterReplay: () => const DataFailure(
          'Le serveur de l\'école a renvoyé une page vide.',
        ),
      );
    }
    if (SessionValidator.isLoginPage(data, unlessContains: dataMarker)) {
      throw _SessionRejected(
        'page de connexion reçue à la place des données',
        afterReplay: _sessionLost,
      );
    }
    return data;
  }

  Future<void> _captureCookies(
    EdcSession session,
    Uri uri,
    Response<String> response,
  ) async {
    final List<String>? setCookies = response.headers['set-cookie'];
    if (setCookies == null || setCookies.isEmpty) return;
    final int before = session.jar.revision;
    session.jar.saveFromResponse(uri, setCookies);
    if (session.jar.revision != before) {
      await _sessions.persistIfCurrent(session);
    }
  }

  static void _throwIfCancelled(CancelToken? cancelToken) {
    if (cancelToken?.isCancelled ?? false) throw const CancelledFailure();
  }
}

/// Accès aux pages de l'école avec UNE session donnée, pendant une opération
/// lancée par [SchoolClient.run].
class SchoolRequester {
  SchoolRequester._(this._client, this.session, this._cancelToken);

  final SchoolClient _client;
  final EdcSession session;
  final CancelToken? _cancelToken;

  ScFormConfig get config => _client._config;

  /// Identifiant de planning (pkEntite). Absent : session incomplète, elle
  /// est rouverte une fois.
  String get planningId {
    final String? id = session.planningId;
    if (id == null || id.isEmpty) {
      throw _SessionRejected(
        'identifiant de planning (pkEntite) absent de la session',
        afterReplay: () => const DataFailure(
          'Identifiant de planning introuvable sur l\'accueil de l\'espace '
          'école.',
        ),
      );
    }
    return id;
  }

  /// URL d'une page `/GaliaEDC/(S(…))/…` (nécessite le segment cookieless).
  Uri galiaEdcUri(String path) {
    final String? segment = session.segment;
    if (segment == null) {
      throw _SessionRejected(
        'segment de session (S(…)) absent',
        afterReplay: _sessionLost,
      );
    }
    return config.schoolUri('${ScFormConfig.galiaEdcPrefix}/$segment$path');
  }

  /// Page HTML de données. [dataMarker] : marqueur d'une page légitime, qui
  /// empêche de la confondre avec une page de connexion.
  Future<String> getPage(Uri uri, {Pattern? dataMarker}) =>
      _client._fetch(this, 'GET', uri, dataMarker: dataMarker);

  /// Postback WebForms (§4.2).
  Future<String> postForm(
    Uri uri,
    Map<String, String> fields, {
    Pattern? dataMarker,
  }) =>
      _client._fetch(this, 'POST', uri, form: fields, dataMarker: dataMarker);
}

final schoolClientProvider = Provider<SchoolClient>((ref) {
  return SchoolClient(
    ref.watch(dioProvider),
    ref.watch(scFormConfigProvider),
    ref.watch(sessionManagerProvider),
    ref.watch(retryPolicyProvider),
  );
});
