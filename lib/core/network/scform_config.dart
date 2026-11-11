import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Paramètres du protocole SC Form / GaliaEDC, issus de la rétro-ingénierie
/// (voir REVERSE_ENGINEERING.md).
///
/// Tout ce qui dépend du serveur est regroupé ici : si SC Form change une URL
/// ou un nom de contrôle WebForms, l'ajustement reste local. Les URL de base
/// sont injectables pour que les tests visent un serveur HTTP local.
class ScFormConfig {
  const ScFormConfig({
    this.apiBaseUrl = 'https://app-api.sc-form.net/api/v1',
    this.schoolBaseUrl = 'https://expernet.sc-form.net',
    this.appOrigin = 'https://app.sc-form.net',
    this.edcLocalId,
  });

  /// API d'authentification globale (REST / JSON / JWT).
  final String apiBaseUrl;

  /// Instance école GaliaEDC (ASP.NET WebForms) : planning et notes.
  final String schoolBaseUrl;

  /// Front officiel, imité par les en-têtes `Origin` / `Referer`.
  final String appOrigin;

  /// Valeur imposée du paramètre `localid` (§2.4). `null` : valeur aléatoire.
  final String? edcLocalId;

  static const String loginPath = '/Account/Login';
  static const String getTokenPath = '/Account/GetToken';
  static const String edcFonctionnalite = 'RedirectEDC';
  static const String edcDefaultPath = '/GaliaEDC/Default.aspx';
  static const String edcTse = '2';
  static const String edcMonoscco = '1';
  static const String planningJournalierPath =
      '/PlanningWeb/PlanningJournalier/Stagiaire';
  static const String galiaEdcPrefix = '/GaliaEDC';
  static const String mesNotesPath = '/Eleve/MesNotes.aspx';
  static const String headerLogiciel = 'SC-Connect';

  /// Cookie ASP.NET qui authentifie réellement les requêtes de données (§2.2).
  static const String authCookieName = '.ASPXAUTH';

  /// Nom WebForms du sélecteur de semestre de la page des notes (§4.1 b).
  static const String periodSelectName = r'ctl00$MainContent$DropDownLstPeriode';

  /// Fin du nom WebForms du sélecteur de classe (cursus) de la même page.
  static const String classSelectSuffix = 'DropDownLstClasse';

  /// Redirections suivies au maximum pendant la poignée de main EDC (§2.2).
  static const int maxEdcHops = 8;

  /// En-têtes posés sur toutes les requêtes (§1.4). Sans `Logiciel`, l'API
  /// refuse la connexion même avec des identifiants valides.
  Map<String, String> get defaultHeaders => {
        'Logiciel': headerLogiciel,
        'Origin': appOrigin,
        'Referer': '$appOrigin/',
        'Accept': 'application/json, text/plain, */*',
      };

  Uri apiUri(String path, [Map<String, String>? query]) =>
      _build(apiBaseUrl, path, query);

  Uri schoolUri(String path, [Map<String, String>? query]) =>
      _build(schoolBaseUrl, path, query);

  static Uri _build(String base, String path, Map<String, String>? query) {
    final Uri uri = Uri.parse('$base$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }
}

/// Configuration courante (surchargée dans les tests).
final scFormConfigProvider = Provider<ScFormConfig>((ref) {
  return const ScFormConfig();
});
