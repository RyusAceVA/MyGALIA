/// Masquage des données sensibles AVANT toute journalisation.
///
/// Règle absolue : aucun mot de passe, cookie, jeton, segment de session ni
/// e-mail n'apparaît dans les journaux. Les en-têtes `Cookie`, `Set-Cookie`
/// et `Authorization` ne sont jamais journalisés (seuls les NOMS des cookies
/// reçus le sont), et les corps de requête/réponse non plus.
abstract final class Redact {
  Redact._();

  static const String mask = '•••';

  /// Paramètres d'URL dont la valeur est masquée (comparaison sans casse).
  static const Set<String> _sensitiveParams = {
    'email',
    'emailscco',
    'tokenscco',
    'token',
    'password',
    'localid',
  };

  /// Segment de session cookieless ASP.NET `(S(…))` : c'est un identifiant
  /// de session, donc un secret.
  static final RegExp _sessionSegment = RegExp(r'\(S\([^)]*\)\)');

  /// URL affichable : segment de session et paramètres sensibles masqués.
  static String uri(Uri uri) {
    final String port = uri.hasPort ? ':${uri.port}' : '';
    final String path = uri.path.replaceAll(_sessionSegment, '(S($mask))');
    final StringBuffer buffer =
        StringBuffer('${uri.scheme}://${uri.host}$port$path');
    if (uri.query.isNotEmpty) {
      buffer.write('?${_query(uri)}');
    }
    return buffer.toString();
  }

  /// Destination d'une redirection (en-tête `Location`, souvent relatif).
  static String location(String? raw, Uri base) {
    if (raw == null || raw.isEmpty) return '(aucune destination)';
    try {
      return uri(base.resolve(raw));
    } on FormatException {
      return '(destination illisible)';
    }
  }

  /// Noms des cookies d'en-têtes `Set-Cookie`, sans jamais leurs valeurs.
  static String cookieNames(Iterable<String> setCookieHeaders) {
    final List<String> names = [
      for (final String header in setCookieHeaders)
        if (header.contains('=')) header.substring(0, header.indexOf('=')).trim(),
    ];
    return names.isEmpty ? '(aucun)' : names.join(', ');
  }

  static String _query(Uri uri) {
    try {
      return uri.queryParametersAll.entries
          .map((MapEntry<String, List<String>> e) =>
              _sensitiveParams.contains(e.key.toLowerCase())
                  ? '${e.key}=$mask'
                  : '${e.key}=${e.value.join(',')}')
          .join('&');
    } on FormatException {
      return mask;
    }
  }
}
