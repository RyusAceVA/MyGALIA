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

  /// Vrai si [body] est une page de connexion (formulaire avec mot de passe).
  ///
  /// [unlessContains] : marqueur d'une page de données légitime ; s'il est
  /// présent, la page n'est pas considérée comme un login (même principe que
  /// l'heuristique d'origine `password` + absence de `/20`, §5.1).
  static bool isLoginPage(String body, {Pattern? unlessContains}) {
    if (!_passwordInput.hasMatch(body)) return false;
    return unlessContains == null || !body.contains(unlessContains);
  }
}
