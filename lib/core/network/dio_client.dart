import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/constants/app_constants.dart';
import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/debug/redact.dart';
import 'package:mygalia/core/network/scform_config.dart';

// =============================================================================
// Client HTTP MyGalia
//
// Un seul [Dio], volontairement « passif » :
//   * aucune redirection n'est suivie automatiquement : une session expirée se
//     manifeste par un 302 vers le login, qu'il faut VOIR pour réagir (sinon
//     le login arrive en 200 et serait parsé comme des données) ;
//   * tous les statuts HTTP sont rendus à l'appelant, qui les interprète selon
//     le contexte (connexion API, poignée de main EDC, page de données) ;
//   * les corps sont lus en texte brut, décodés explicitement (HTML ou JSON) ;
//   * aucun cookie n'est géré ici : chaque session école possède son propre
//     cookie jar (voir SchoolClient), jeté à chaque renouvellement.
//
// Il n'existe aucun cache HTTP : chaque requête part réellement sur le réseau.
// =============================================================================

/// Construit le client. Les délais sont surchargeables pour les tests.
Dio createScFormDio(
  ScFormConfig config, {
  Duration? connectTimeout,
  Duration? sendTimeout,
  Duration? receiveTimeout,
}) {
  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: connectTimeout ?? AppConstants.connectTimeout,
      sendTimeout: sendTimeout ?? AppConstants.sendTimeout,
      receiveTimeout: receiveTimeout ?? AppConstants.receiveTimeout,
      headers: config.defaultHeaders,
      followRedirects: false,
      validateStatus: (_) => true,
      responseType: ResponseType.plain,
    ),
  );
  if (kDebugMode) {
    dio.interceptors.add(NetworkLogInterceptor());
  }
  return dio;
}

/// Client applicatif, injecté dans les couches `data/`.
final dioProvider = Provider<Dio>((ref) {
  final Dio dio = createScFormDio(ref.watch(scFormConfigProvider));
  ref.onDispose(dio.close);
  return dio;
});

/// Journal réseau structuré (debug uniquement).
///
/// Trace méthode, URL masquée, statut, durée, taille, destination des
/// redirections et NOMS des cookies reçus. Jamais : en-têtes Cookie /
/// Set-Cookie / Authorization, corps de requête ou de réponse.
class NetworkLogInterceptor extends Interceptor {
  static const String _startedAtKey = 'mygalia.startedAt';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAtKey] = DateTime.now();
    AppLog.http('→ ${options.method} ${Redact.uri(options.uri)}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final RequestOptions options = response.requestOptions;
    final Object? data = response.data;
    final StringBuffer line = StringBuffer(
      '← ${response.statusCode} ${options.method} ${Redact.uri(options.uri)} '
      '(${_elapsedMs(options)} ms, '
      '${data is String ? '${data.length} car.' : 'corps non textuel'})',
    );
    final String? location = response.headers['location']?.firstOrNull;
    if (location != null) {
      line.write(' · redirection vers ${Redact.location(location, options.uri)}');
    }
    final List<String>? setCookies = response.headers['set-cookie'];
    if (setCookies != null && setCookies.isNotEmpty) {
      line.write(' · cookies reçus : ${Redact.cookieNames(setCookies)}');
    }
    AppLog.http(line.toString());
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final RequestOptions options = err.requestOptions;
    AppLog.http(
      '✗ ${err.type.name} ${options.method} ${Redact.uri(options.uri)} '
      '(${_elapsedMs(options)} ms, cause : ${err.error?.runtimeType ?? '-'})',
    );
    handler.next(err);
  }

  static int _elapsedMs(RequestOptions options) {
    final Object? startedAt = options.extra[_startedAtKey];
    if (startedAt is! DateTime) return -1;
    return DateTime.now().difference(startedAt).inMilliseconds;
  }
}
