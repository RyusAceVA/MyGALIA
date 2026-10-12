import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/debug/redact.dart';
import 'package:mygalia/core/network/cookie_jar.dart';
import 'package:mygalia/core/network/dio_client.dart';
import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/network/scform_config.dart';
import 'package:mygalia/core/session/session_validator.dart';
import 'package:mygalia/features/auth/domain/edc_session.dart';

/// Phase 2 de la cinétique (§2.2) : échange du jeton de transition contre une
/// session ASP.NET sur l'instance école.
///
/// La chaîne de redirections est suivie À LA MAIN pour capter le
/// `Set-Cookie` de chaque saut (dont `.ASPXAUTH`) et le segment `(S(…))`.
/// Chaque ouverture part d'un cookie jar NEUF.
class EdcSessionBootstrap {
  EdcSessionBootstrap(
    this._dio,
    this._config, {
    Random? random,
    DateTime Function()? clock,
  })  : _random = random ?? Random.secure(),
        _clock = clock ?? DateTime.now;

  final Dio _dio;
  final ScFormConfig _config;
  final Random _random;
  final DateTime Function() _clock;

  static final RegExp _segmentPattern = RegExp(r'\(S\([^)]+\)\)');

  /// Lien vers le planning sur la page d'accueil, puis variable JS de repli.
  static final List<RegExp> _planningIdPatterns = [
    RegExp(r'PlanningJournalier/Stagiaire\?id=(\d+)'),
    RegExp(r"G_PkEntitePlanning\s*=\s*'(\d+)'"),
  ];

  static const String _base62 =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  Future<EdcSession> open({
    required String email,
    required String transitionToken,
    required int generation,
    CancelToken? cancelToken,
  }) async {
    final CookieJar jar = CookieJar();
    Uri uri = _config.schoolUri(ScFormConfig.edcDefaultPath, {
      'emailscco': email,
      'tokenscco': transitionToken,
      'tse': ScFormConfig.edcTse,
      'monoscco': ScFormConfig.edcMonoscco,
      'localid': _config.edcLocalId ?? _generateLocalId(),
    });
    String? segment;

    for (int hop = 0; hop <= ScFormConfig.maxEdcHops; hop++) {
      final Response<String> response = await _get(uri, jar, cancelToken);
      jar.saveFromResponse(
        uri,
        response.headers['set-cookie'] ?? const <String>[],
      );
      segment = _segmentPattern.stringMatch(uri.path) ?? segment;
      final int status = response.statusCode ?? 0;

      if (SessionValidator.isRedirect(status)) {
        final String? location = response.headers['location']?.firstOrNull;
        if (location == null || location.isEmpty) {
          throw const SessionFailure(
            'Ouverture de la session école impossible : redirection sans '
            'destination.',
          );
        }
        uri = uri.resolve(location);
        AppLog.session(
          'poignée de main EDC, saut ${hop + 1} : $status vers '
          '${Redact.uri(uri)}',
        );
        continue;
      }
      if (status == 200) {
        return _finish(uri, response.data ?? '', jar, segment, generation);
      }
      if (status >= 500) throw ServerFailure.status(status);
      throw SessionFailure(
        'L\'espace école a refusé l\'ouverture de session (erreur $status).',
        code: status,
      );
    }
    throw const SessionFailure(
      'Ouverture de la session école impossible : trop de redirections.',
    );
  }

  EdcSession _finish(
    Uri finalUri,
    String body,
    CookieJar jar,
    String? segmentSoFar,
    int generation,
  ) {
    String? planningId;
    for (final RegExp pattern in _planningIdPatterns) {
      planningId = pattern.firstMatch(body)?.group(1);
      if (planningId != null) break;
    }
    if (planningId == null && SessionValidator.isLoginPage(body)) {
      throw const SessionFailure(
        'L\'espace école a renvoyé sa page de connexion au lieu de l\'accueil.',
      );
    }
    if (!jar.contains(ScFormConfig.authCookieName)) {
      throw const SessionFailure(
        'Session école incomplète : cookie d\'authentification absent.',
      );
    }
    final String? segment = _segmentPattern.stringMatch(finalUri.path) ??
        segmentSoFar ??
        _segmentPattern.stringMatch(body);
    AppLog.session(
      'session école ouverte (génération $generation) · cookies : '
      '${jar.names.join(', ')} · segment ${segment == null ? 'ABSENT' : 'présent'}'
      ' · pkEntite ${planningId == null ? 'ABSENT' : 'trouvé'}',
    );
    return EdcSession(
      jar: jar,
      segment: segment,
      planningId: planningId,
      generation: generation,
      createdAt: _clock(),
    );
  }

  Future<Response<String>> _get(
    Uri uri,
    CookieJar jar,
    CancelToken? cancelToken,
  ) async {
    final String? cookie = jar.headerFor(uri);
    try {
      return await _dio.getUri<String>(
        uri,
        options: Options(headers: {if (cookie != null) 'Cookie': cookie}),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  /// Identifiant de corrélation imitant celui du SPA officiel (§2.4).
  String _generateLocalId() => String.fromCharCodes(
        List<int>.generate(
          20,
          (_) => _base62.codeUnitAt(_random.nextInt(_base62.length)),
        ),
      );
}

final edcSessionBootstrapProvider = Provider<EdcSessionBootstrap>((ref) {
  return EdcSessionBootstrap(
    ref.watch(dioProvider),
    ref.watch(scFormConfigProvider),
  );
});
