import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/network/dio_client.dart';
import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/network/retry_policy.dart';
import 'package:mygalia/core/network/scform_config.dart';
import 'package:mygalia/core/storage/secure_storage_service.dart';

/// Signal interne : `GetToken` a refusé le jeton API (401/403). Il faut se
/// reconnecter à l'API. Jamais affiché à l'utilisateur.
class ApiTokenRejected implements Exception {
  const ApiTokenRejected(this.status);

  final int status;
}

/// Phase 1 de la cinétique (§2.1) : connexion à l'API globale (JWT) et
/// obtention du jeton de transition vers GaliaEDC.
class AuthRepository {
  AuthRepository(this._dio, this._config, this._retry);

  final Dio _dio;
  final ScFormConfig _config;
  final RetryPolicy _retry;

  /// Le nom du champ est bruité côté serveur (« accesToken ») : on accepte
  /// plusieurs variantes, éventuellement imbriquées (§2.1).
  static const List<String> _tokenKeys = [
    'accesToken',
    'accessToken',
    'token',
    'jwt',
  ];

  static const List<String> _messageKeys = [
    'message',
    'Message',
    'errorMessage',
    'error_description',
  ];

  static final RegExp _rawToken = RegExp(r'^[A-Za-z0-9._\-]+$');

  /// `POST /Account/Login?DoubleAuth=true`.
  ///
  /// Lève [InvalidCredentialsFailure] si SC Form refuse les identifiants :
  /// cette erreur n'est jamais relancée automatiquement. Un 400 ou un 403 qui
  /// ne vient pas de l'API elle-même (voir [_refusesCredentials]) lève une
  /// [ServerFailure] : il ne doit ni déconnecter ni effacer le coffre.
  Future<ApiToken> login(Credentials credentials, {CancelToken? cancelToken}) {
    return _retry.run(
      'connexion API',
      () async {
        final Response<String> response = await _guard(
          () => _dio.postUri<String>(
            _config.apiUri(ScFormConfig.loginPath, const {'DoubleAuth': 'true'}),
            // Corps encodé à la main (§2.1) : aucune ambiguïté de transformer.
            data: jsonEncode({
              'email': credentials.email,
              'password': credentials.password,
            }),
            options: Options(contentType: Headers.jsonContentType),
            cancelToken: cancelToken,
          ),
        );
        final int status = response.statusCode ?? 0;
        if (status == 200) {
          final Object? json = _decodeJson(response.data);
          final String? token = deepFindString(json, _tokenKeys);
          if (token == null) {
            throw const SessionFailure(
              'Connexion SC Form inattendue : aucun jeton dans la réponse '
              '(double authentification activée ?).',
            );
          }
          final String? expires = deepFindString(json, const ['expires']);
          AppLog.auth('connexion API réussie (jeton valable jusqu\'à '
              '${expires ?? 'une date inconnue'})');
          return ApiToken(
            token,
            expiresAt: expires == null ? null : DateTime.tryParse(expires),
          );
        }
        if (status == 400 || status == 401 || status == 403) {
          if (_refusesCredentials(status, response.data)) {
            AppLog.auth('connexion API refusée (HTTP $status)');
            throw InvalidCredentialsFailure(
              _serverMessage(response.data) ??
                  'Identifiant ou mot de passe refusé par SC Form.',
              code: status,
            );
          }
          // Blocage en amont de l'API (pare-feu, limite de débit) ou requête
          // jugée mal formée : rien ne dit que le mot de passe est faux.
          AppLog.auth(
            'connexion API bloquée (HTTP $status) sans verdict sur les '
            'identifiants',
          );
          throw ServerFailure(
            'SC Form a bloqué la connexion sans se prononcer sur vos '
            'identifiants (erreur $status). Réessayez plus tard.',
            code: status,
          );
        }
        throw ServerFailure.status(status);
      },
      cancelToken: cancelToken,
    );
  }

  /// `GET /Account/GetToken?email=…&fonctionnalite=RedirectEDC` (Bearer).
  ///
  /// Pas de relance ici : le jeton obtenu est à usage unique, c'est l'unité
  /// « jeton + poignée de main » qui est relancée d'un bloc.
  Future<String> getEdcTransitionToken({
    required String email,
    required ApiToken token,
    CancelToken? cancelToken,
  }) async {
    final Response<String> response = await _guard(
      () => _dio.getUri<String>(
        _config.apiUri(ScFormConfig.getTokenPath, {
          'email': email,
          'fonctionnalite': ScFormConfig.edcFonctionnalite,
        }),
        options: Options(headers: {'Authorization': 'Bearer ${token.value}'}),
        cancelToken: cancelToken,
      ),
    );
    final int status = response.statusCode ?? 0;
    if (status == 401 || status == 403) throw ApiTokenRejected(status);
    if (status != 200) throw ServerFailure.status(status);

    final String body = (response.data ?? '').trim();
    String? transition;
    try {
      final Object? json = jsonDecode(body);
      transition = json is String ? json : deepFindString(json, const ['token']);
    } on FormatException {
      // Certains serveurs renvoient le jeton brut, sans JSON.
      transition = _rawToken.hasMatch(body) ? body : null;
    }
    if (transition == null || transition.isEmpty) {
      throw const DataFailure(
        'Réponse de SC Form illisible (jeton de transition absent).',
      );
    }
    return transition;
  }

  /// Vrai si la réponse est un verdict de l'API sur les identifiants.
  ///
  ///  * 401 : toujours ;
  ///  * 400 / 403 : seulement si le corps est un objet JSON, donc écrit par
  ///    l'API. Une page HTML ou un corps vide viennent d'un intermédiaire
  ///    (pare-feu, limite de débit, maintenance). Un 400 de validation
  ///    ASP.NET (clé `errors`) signale une requête mal formée, pas un mauvais
  ///    mot de passe.
  static bool _refusesCredentials(int status, String? body) {
    if (status == 401) return true;
    if (body == null || body.trim().isEmpty) return false;
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return false;
    }
    return json is Map && json['errors'] is! Map;
  }

  static Future<Response<String>> _guard(
    Future<Response<String>> Function() request,
  ) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  static Object? _decodeJson(String? body) {
    if (body == null || body.trim().isEmpty) {
      throw const DataFailure('Réponse vide de l\'API SC Form.');
    }
    try {
      return jsonDecode(body);
    } on FormatException catch (e) {
      throw DataFailure('Réponse illisible de l\'API SC Form.', cause: e);
    }
  }

  /// Message d'erreur fourni par le serveur, s'il est court et lisible.
  static String? _serverMessage(String? body) {
    if (body == null || body.trim().isEmpty) return null;
    try {
      final String? message = deepFindString(jsonDecode(body), _messageKeys);
      if (message != null && message.length <= 200) return message;
    } on FormatException {
      // Corps non JSON : message par défaut.
    }
    return null;
  }
}

/// Première chaîne associée à l'une des [keys], en cherchant d'abord au
/// niveau courant puis récursivement (cartes et listes imbriquées).
String? deepFindString(Object? node, List<String> keys) {
  if (node is Map) {
    for (final String key in keys) {
      final Object? value = node[key];
      if (value is String && value.isNotEmpty) return value;
    }
    for (final Object? value in node.values) {
      final String? found = deepFindString(value, keys);
      if (found != null) return found;
    }
  } else if (node is List) {
    for (final Object? value in node) {
      final String? found = deepFindString(value, keys);
      if (found != null) return found;
    }
  }
  return null;
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(dioProvider),
    ref.watch(scFormConfigProvider),
    ref.watch(retryPolicyProvider),
  );
});
