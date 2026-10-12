import 'package:mygalia/core/network/cookie_jar.dart';

/// Session ouverte sur l'instance école GaliaEDC (§2.2 de la rétro-ingénierie).
class EdcSession {
  EdcSession({
    required this.jar,
    required this.segment,
    required this.planningId,
    required this.generation,
    required this.createdAt,
  });

  /// Cookies de CETTE session (dont `.ASPXAUTH`). Jamais partagé avec une
  /// autre session.
  final CookieJar jar;

  /// Segment cookieless `(S(…))`, indispensable pour les pages `/GaliaEDC/…`.
  final String? segment;

  /// Identifiant interne du planning du stagiaire (`pkEntite`).
  final String? planningId;

  /// Numéro croissant attribué à chaque ouverture : permet de savoir si une
  /// session a déjà été remplacée (voir `SessionManager.renew`).
  final int generation;

  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'cookies': jar.toJson(),
        'segment': segment,
        'planningId': planningId,
        'generation': generation,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  /// Session relue du coffre, ou `null` si le contenu est incomplet ou
  /// corrompu (elle sera alors simplement rouverte).
  static EdcSession? tryFromJson(Map<String, Object?> json) {
    try {
      final Object? segment = json['segment'];
      final Object? planningId = json['planningId'];
      return EdcSession(
        jar: CookieJar.fromJson(json['cookies']),
        segment: segment is String && segment.isNotEmpty ? segment : null,
        planningId:
            planningId is String && planningId.isNotEmpty ? planningId : null,
        generation: json['generation']! as int,
        createdAt: DateTime.parse(json['createdAt']! as String),
      );
    } on Object {
      return null;
    }
  }
}
