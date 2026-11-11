/// Constantes globales de l'application (non sensibles).
///
/// Les paramètres du protocole SC Form (URL, en-têtes, chemins) sont dans
/// `ScFormConfig` ; les secrets ne transitent que par le coffre chiffré
/// (`SecureStorageService`).
abstract final class AppConstants {
  AppConstants._();

  static const String appName = 'MyGalia';

  /// Délais réseau (Dio). Chaque requête est bornée : aucune ne peut rester
  /// pendante indéfiniment. Les relances automatiques (voir `RetryPolicy`)
  /// s'ajoutent à ces délais.
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration sendTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// Délais d'attente avant chaque relance automatique d'une erreur
  /// transitoire (timeout, 5xx, coupure). Deux relances au maximum.
  static const List<Duration> retryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 3),
  ];

  /// À l'ouverture d'un écran, le cache plus récent que ce délai est affiché
  /// sans interroger le serveur (navigation entre semaines, retour rapide).
  static const Duration initialFetchAfter = Duration(minutes: 5);

  /// Au retour au premier plan ou du réseau, les données plus anciennes que
  /// ce délai sont rechargées automatiquement.
  static const Duration autoRefreshAfter = Duration(minutes: 30);

  /// Intervalle minimal entre deux rechargements AUTOMATIQUES d'un même
  /// écran (anti-rafale si le réseau oscille).
  static const Duration minAutoRefreshInterval = Duration(seconds: 20);

  /// Noms des boîtes Hive utilisées pour le cache local.
  static const String settingsBox = 'settings_box';

  /// Cache chiffré (AES, clé dans le coffre). [legacyCacheBox] est l'ancienne
  /// boîte en clair, supprimée au démarrage.
  static const String cacheBox = 'cache_box_v2';
  static const String legacyCacheBox = 'cache_box';
}
