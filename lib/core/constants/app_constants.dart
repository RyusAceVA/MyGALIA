/// Constantes globales de l'application (non sensibles).
///
/// Les secrets (URL privées, clés) n'ont PAS leur place ici : ils passeront
/// par la configuration d'environnement / [flutter_secure_storage].
abstract final class AppConstants {
  AppConstants._();

  static const String appName = 'MyGalia';

  /// Base URL de l'API SC-Form (placeholder — à définir à l'étape réseau).
  static const String apiBaseUrl = 'https://api.example.com';

  /// Délais réseau par défaut (Dio).
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// Noms des boîtes Hive utilisées pour le cache local.
  static const String settingsBox = 'settings_box';
  static const String cacheBox = 'cache_box';

  /// Clés de stockage sécurisé.
  static const String kAccessToken = 'access_token';
  static const String kRefreshToken = 'refresh_token';

  /// Cookie de session SC-Form (le portail fonctionne par session serveur :
  /// on persiste le cookie renvoyé au login pour le ré-injecter ensuite).
  static const String kSessionCookie = 'sc_form_session_cookie';
}
