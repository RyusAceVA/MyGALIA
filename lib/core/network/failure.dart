import 'dart:io';

import 'package:dio/dio.dart';

/// Erreurs typées de l'application.
///
/// Classe scellée : un `switch` côté UI doit traiter tous les cas. Chaque
/// variante porte un [message] présentable tel quel à l'utilisateur et, pour
/// le diagnostic, la [cause] technique d'origine (jamais affichée).
///
/// Seules les erreurs [isTransient] sont relancées automatiquement
/// (voir `RetryPolicy`).
sealed class Failure implements Exception {
  const Failure(this.message, {this.code, this.cause});

  /// Message compréhensible, affichable à l'utilisateur.
  final String message;

  /// Code technique optionnel (souvent le statut HTTP).
  final int? code;

  /// Erreur technique d'origine, conservée pour les journaux de debug.
  final Object? cause;

  /// Erreur passagère : une nouvelle tentative automatique a du sens.
  bool get isTransient => false;

  @override
  String toString() => '$runtimeType(code: $code, message: $message)';
}

/// Nature d'un problème de transport.
enum NetworkIssue { offline, timeout, interrupted }

/// Pas de réseau, délai dépassé ou connexion coupée. Toujours transitoire.
final class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {required this.issue, super.cause});

  factory NetworkFailure.offline([Object? cause]) => NetworkFailure(
        'Pas de connexion Internet. Vérifiez votre réseau puis réessayez.',
        issue: NetworkIssue.offline,
        cause: cause,
      );

  factory NetworkFailure.timeout([Object? cause]) => NetworkFailure(
        'Le serveur SC Form met trop de temps à répondre. '
        'Réessayez dans un instant.',
        issue: NetworkIssue.timeout,
        cause: cause,
      );

  factory NetworkFailure.interrupted([Object? cause]) => NetworkFailure(
        'La connexion au serveur SC Form a été interrompue. Réessayez.',
        issue: NetworkIssue.interrupted,
        cause: cause,
      );

  final NetworkIssue issue;

  @override
  bool get isTransient => true;
}

/// Réponse d'erreur du serveur. Transitoire seulement pour un 5xx.
final class ServerFailure extends Failure {
  const ServerFailure(super.message, {super.code, super.cause});

  factory ServerFailure.status(int status) => ServerFailure(
        status >= 500
            ? 'Le serveur SC Form rencontre un problème (erreur $status). '
                'Réessayez plus tard.'
            : 'Réponse inattendue du serveur SC Form (erreur $status).',
        code: status,
      );

  @override
  bool get isTransient => (code ?? 0) >= 500;
}

/// La session (API ou espace école) n'a pas pu être ouverte ou rétablie.
final class SessionFailure extends Failure {
  const SessionFailure(super.message, {super.code, super.cause});
}

/// Identifiants refusés par SC Form. C'est le SEUL cas qui renvoie
/// l'utilisateur à l'écran de connexion.
final class InvalidCredentialsFailure extends Failure {
  const InvalidCredentialsFailure(super.message, {super.code, super.cause});
}

/// Aucun identifiant enregistré : il faut se connecter.
final class SignedOutFailure extends Failure {
  const SignedOutFailure([
    super.message = 'Connectez-vous pour accéder à vos données.',
  ]);
}

/// Données reçues illisibles : page vide, format inattendu, parsing impossible.
final class DataFailure extends Failure {
  const DataFailure(super.message, {super.code, super.cause});
}

/// Erreur de persistance locale (coffre chiffré, Hive).
final class CacheFailure extends Failure {
  const CacheFailure(super.message, {super.code, super.cause});
}

/// Requête annulée volontairement (écran fermé, déconnexion). Jamais affichée.
final class CancelledFailure extends Failure {
  const CancelledFailure() : super('Requête annulée.');
}

/// Filet de sécurité pour tout le reste.
final class UnknownFailure extends Failure {
  const UnknownFailure(super.message, {super.code, super.cause});
}

/// Traduit une erreur de transport Dio en [Failure], sans perdre la cause.
///
/// Les codes HTTP ne passent pas par ici : le client est configuré pour
/// rendre toutes les réponses à l'appelant, qui les interprète selon le
/// contexte (connexion API, poignée de main EDC, page de données).
Failure failureFromDioException(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return NetworkFailure.timeout(e);
    case DioExceptionType.connectionError:
      return _isOffline(e.error)
          ? NetworkFailure.offline(e)
          : NetworkFailure.interrupted(e);
    case DioExceptionType.badCertificate:
      return ServerFailure(
        'Certificat de sécurité du serveur invalide : connexion refusée.',
        cause: e,
      );
    case DioExceptionType.cancel:
      return const CancelledFailure();
    case DioExceptionType.badResponse:
      return ServerFailure.status(e.response?.statusCode ?? 0);
    case DioExceptionType.unknown:
      final Object? error = e.error;
      if (error is SocketException) {
        return _isOffline(error)
            ? NetworkFailure.offline(e)
            : NetworkFailure.interrupted(e);
      }
      if (error is HttpException || error is TlsException) {
        return NetworkFailure.interrupted(e);
      }
      if (error is FormatException) {
        return DataFailure('Réponse du serveur illisible.', cause: e);
      }
      return UnknownFailure('Une erreur inattendue est survenue.', cause: e);
  }
}

/// Vrai si l'erreur indique une absence de réseau (DNS ou route impossible).
bool _isOffline(Object? error) {
  if (error is! SocketException) return false;
  final String message = error.message.toLowerCase();
  final String osMessage = error.osError?.message.toLowerCase() ?? '';
  final int? code = error.osError?.errorCode;
  return message.contains('failed host lookup') ||
      osMessage.contains('no address associated') ||
      osMessage.contains('network is unreachable') ||
      code == 7 || // EAI_NODATA / « No address associated with hostname »
      code == 101; // ENETUNREACH
}
