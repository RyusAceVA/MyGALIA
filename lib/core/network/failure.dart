import 'package:dio/dio.dart';

/// Représentation typée et exhaustive des erreurs de l'application.
///
/// On expose une [Failure] scellée (`sealed`) : le compilateur force alors le
/// traitement de **tous** les cas dans un `switch` côté UI/contrôleur, ce qui
/// évite les erreurs oubliées. La couche `data/` des features convertit les
/// exceptions techniques (Dio, Hive, plateforme) en une de ces variantes, si
/// bien que la couche `domain/`/`presentation/` ne manipule jamais de
/// `DioException` brute.
sealed class Failure {
  const Failure(this.message, {this.code});

  /// Message lisible, présentable à l'utilisateur (ou loggable).
  final String message;

  /// Code technique optionnel (souvent le status HTTP pour un [ServerFailure]).
  final int? code;

  @override
  String toString() => '$runtimeType(code: $code, message: $message)';

  // ---------------------------------------------------------------------------
  // Fabrique de mapping Dio -> Failure.
  //
  // Centralisée ici pour être réutilisable aussi bien dans l'intercepteur
  // d'erreurs que dans un éventuel try/catch manuel côté repository.
  // ---------------------------------------------------------------------------
  factory Failure.fromDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const NetworkFailure(
          'Délai de connexion dépassé. Vérifiez votre réseau.',
        );

      case DioExceptionType.connectionError:
        return const NetworkFailure(
          'Impossible de joindre le serveur. Vérifiez votre connexion.',
        );

      case DioExceptionType.badCertificate:
        return const NetworkFailure('Certificat de sécurité invalide.');

      case DioExceptionType.cancel:
        return const NetworkFailure('Requête annulée.');

      case DioExceptionType.badResponse:
        return _fromStatusCode(e.response?.statusCode);

      case DioExceptionType.unknown:
        return const UnknownFailure('Une erreur inattendue est survenue.');
    }
  }

  /// Traduit un status HTTP en [Failure] métier.
  static Failure _fromStatusCode(int? status) {
    switch (status) {
      case 400:
        return ServerFailure('Requête invalide.', code: status);
      case 401:
        return AuthFailure(
          'Session expirée ou identifiants invalides.',
          code: status,
        );
      case 403:
        return AuthFailure('Accès refusé.', code: status);
      case 404:
        return ServerFailure('Ressource introuvable.', code: status);
      case 500:
      case 502:
      case 503:
        return ServerFailure(
          'Le serveur SC-Form est momentanément indisponible.',
          code: status,
        );
      default:
        return ServerFailure(
          'Erreur serveur (${status ?? 'inconnu'}).',
          code: status,
        );
    }
  }
}

/// Problème de connectivité / transport (timeout, pas de réseau, DNS…).
final class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {super.code});
}

/// Réponse d'erreur émise par le serveur (5xx, 4xx non liés à l'auth).
final class ServerFailure extends Failure {
  const ServerFailure(super.message, {super.code});
}

/// Échec d'authentification / autorisation (401, 403, session invalide).
///
/// Distingué des autres pour permettre un traitement dédié : redirection vers
/// l'écran de login, purge de la session stockée, etc.
final class AuthFailure extends Failure {
  const AuthFailure(super.message, {super.code});
}

/// Erreur de persistance locale (Hive / secure storage).
final class CacheFailure extends Failure {
  const CacheFailure(super.message, {super.code});
}

/// Filet de sécurité pour tout ce qui n'entre dans aucune autre catégorie.
final class UnknownFailure extends Failure {
  const UnknownFailure(super.message, {super.code});
}
