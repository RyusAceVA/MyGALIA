import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/constants/app_constants.dart';
import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/storage/secure_storage_service.dart';

// =============================================================================
// Client réseau MyGalia
//
// Un unique [Dio] configuré + trois intercepteurs, dans l'ordre de la chaîne :
//   1. AuthInterceptor   -> injecte la session SC-Form dans chaque requête.
//   2. LoggingInterceptor-> trace requêtes/réponses/erreurs (debug uniquement).
//   3. ErrorInterceptor  -> convertit toute DioException en [Failure] typée.
//
// L'ordre compte : on veut logger la requête déjà enrichie de ses headers, et
// la conversion en Failure doit être le dernier maillon (elle "termine" l'erreur).
// =============================================================================

/// Injecte les headers de session SC-Form.
///
/// SC-Form est un portail à **session serveur** : le login renvoie un cookie
/// (ex. `JSESSIONID`) qu'il faut renvoyer tel quel à chaque requête suivante.
/// On lit ce cookie depuis le stockage sécurisé et on le pose en header
/// `Cookie`. Tant que l'utilisateur n'est pas connecté, la clé est absente et
/// l'intercepteur ne fait rien — la structure est donc déjà prête pour l'auth.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._storage);

  final SecureStorageService _storage;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final String? sessionCookie =
        await _storage.getString(AppConstants.kSessionCookie);

    if (sessionCookie != null && sessionCookie.isNotEmpty) {
      options.headers['Cookie'] = sessionCookie;
    }

    // Point d'extension : dès que SC-Form fournira un token Bearer, l'ajouter
    // ici via options.headers['Authorization'] = 'Bearer <token>'.

    handler.next(options);
  }
}

/// Logging concis et lisible, actif uniquement en debug.
///
/// On évite de dumper les corps complets (potentiellement volumineux ou
/// sensibles) : on se limite à la ligne de requête, au status et aux erreurs.
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      developer.log(
        '→ ${options.method} ${options.uri}',
        name: 'MyGalia.net',
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      developer.log(
        '← ${response.statusCode} ${response.requestOptions.uri}',
        name: 'MyGalia.net',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      developer.log(
        '✗ ${err.response?.statusCode ?? err.type.name} '
        '${err.requestOptions.uri}',
        name: 'MyGalia.net',
        error: err.message,
      );
    }
    handler.next(err);
  }
}

/// Convertit chaque [DioException] en [Failure] métier.
///
/// On n'avale pas l'erreur : on la propage toujours (`handler.next`), mais on
/// glisse la [Failure] typée dans `err.error`. La couche `data/` peut alors
/// faire `on DioException catch (e) => e.error as Failure` sans reparser le type.
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final Failure failure = Failure.fromDioException(err);
    handler.next(err.copyWith(error: failure));
  }
}

/// Provider du [Dio] applicatif, prêt à être injecté dans les repositories.
///
/// `ref.watch(secureStorageServiceProvider)` câble l'AuthInterceptor sur le
/// même service de stockage que le reste de l'app. Manuel (sans codegen) pour
/// rester compilable sans build_runner.
final dioProvider = Provider<Dio>((ref) {
  final SecureStorageService storage =
      ref.watch(secureStorageServiceProvider);

  final Dio dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: AppConstants.connectTimeout,
      receiveTimeout: AppConstants.receiveTimeout,
      // SC-Form répond souvent en HTML/formulaire ; on ne force pas le JSON,
      // on laissera chaque appel préciser son `responseType` si besoin.
      headers: {'Accept': '*/*'},
      // On gère nous-mêmes les statuts d'erreur via l'ErrorInterceptor : on
      // laisse Dio ne « valider » que les 2xx (comportement par défaut).
    ),
  );

  dio.interceptors.addAll([
    AuthInterceptor(storage),
    LoggingInterceptor(),
    ErrorInterceptor(),
  ]);

  return dio;
});
