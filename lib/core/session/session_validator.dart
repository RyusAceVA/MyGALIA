/// Reconnaissance des réponses qui signifient « session invalide ».
///
/// Utilisé par la poignée de main EDC et par `SchoolClient`, le point
/// d'entrée unique des requêtes de données.
abstract final class SessionValidator {
  SessionValidator._();

  /// Champ de saisie de mot de passe : la signature d'un formulaire de login.
  static final RegExp _passwordInput = RegExp(
    r'''<input\b[^>]*\btype\s*=\s*["']?password\b''',
    caseSensitive: false,
  );

  static bool isRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  /// Vrai si [body] contient un formulaire de connexion (champ mot de passe).
  /// À n'utiliser que sur une page dépourvue de repère de données légitime
  /// (même principe que l'heuristique d'origine `password` + absence de
  /// `/20`, §5.1).
  static bool isLoginPage(String body) => _passwordInput.hasMatch(body);
}
