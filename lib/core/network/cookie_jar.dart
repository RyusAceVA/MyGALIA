import 'dart:io' show Cookie;

import 'package:flutter/foundation.dart';

/// Un cookie conservé par [CookieJar].
@immutable
class StoredCookie {
  const StoredCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.hostOnly,
    required this.secure,
    this.expiresAt,
  });

  final String name;
  final String value;

  /// Domaine en minuscules, sans point initial.
  final String domain;
  final String path;

  /// Vrai si le cookie n'avait pas d'attribut `Domain` : il n'est alors
  /// renvoyé qu'à l'hôte exact qui l'a posé.
  final bool hostOnly;
  final bool secure;

  /// `null` : cookie de session (vit aussi longtemps que la session école).
  final DateTime? expiresAt;

  bool isExpired(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now);

  /// Même identité au sens RFC 6265 : (nom, domaine, chemin).
  bool sameIdentity(StoredCookie other) =>
      name == other.name && domain == other.domain && path == other.path;

  Map<String, Object?> toJson() => {
        'n': name,
        'v': value,
        'd': domain,
        'p': path,
        'h': hostOnly,
        's': secure,
        'e': expiresAt?.toUtc().toIso8601String(),
      };

  static StoredCookie fromJson(Map<String, Object?> json) {
    final Object? expires = json['e'];
    return StoredCookie(
      name: json['n']! as String,
      value: json['v']! as String,
      domain: json['d']! as String,
      path: json['p']! as String,
      hostOnly: json['h']! as bool,
      secure: json['s']! as bool,
      expiresAt: expires is String ? DateTime.parse(expires) : null,
    );
  }
}

/// Cookie jar minimal et strict, propre à UNE session école.
///
/// Règles (RFC 6265, simplifiée) :
///  * un cookie est identifié par (nom, domaine, chemin) : une nouvelle
///    valeur REMPLACE l'ancienne, il n'y a jamais de doublon ;
///  * `Max-Age<=0` ou `Expires` passé supprime le cookie ;
///  * un cookie n'est envoyé qu'aux hôtes et chemins qui lui correspondent,
///    et un cookie `Secure` uniquement en HTTPS ;
///  * un `Domain` étranger à l'hôte qui répond est refusé.
///
/// À chaque renouvellement de session, un jar NEUF est créé : les cookies
/// d'une session expirée ne se mélangent jamais à ceux de la suivante.
class CookieJar {
  CookieJar([Iterable<StoredCookie> cookies = const <StoredCookie>[]]) {
    _cookies.addAll(cookies);
  }

  factory CookieJar.fromJson(Object? json) {
    if (json is! List) throw const FormatException('cookie jar invalide');
    return CookieJar([
      for (final Object? item in json)
        StoredCookie.fromJson((item! as Map<Object?, Object?>).cast<String, Object?>()),
    ]);
  }

  final List<StoredCookie> _cookies = <StoredCookie>[];
  int _revision = 0;

  /// Change à chaque modification (pour savoir s'il faut persister).
  int get revision => _revision;

  List<StoredCookie> get cookies => List<StoredCookie>.unmodifiable(_cookies);

  bool get isEmpty => _cookies.isEmpty;

  Iterable<String> get names => _cookies.map((StoredCookie c) => c.name);

  bool contains(String name) =>
      _cookies.any((StoredCookie c) => c.name.toLowerCase() == name.toLowerCase());

  /// Enregistre les en-têtes `Set-Cookie` d'une réponse à [uri].
  void saveFromResponse(
    Uri uri,
    Iterable<String> setCookieHeaders, {
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();
    for (final String header in setCookieHeaders) {
      final (StoredCookie, bool)? parsed = _parse(header, uri, at);
      if (parsed == null) continue;
      final (StoredCookie cookie, bool expired) = parsed;
      final int existing = _cookies.indexWhere(cookie.sameIdentity);
      if (!expired && existing >= 0 && _sameContent(_cookies[existing], cookie)) {
        continue; // Rien de neuf : inutile de persister à nouveau.
      }
      if (existing >= 0) _cookies.removeAt(existing);
      if (!expired) _cookies.add(cookie);
      if (!expired || existing >= 0) _revision++;
    }
  }

  /// Valeur de l'en-tête `Cookie` pour [uri], ou `null` si aucun cookie ne
  /// correspond. Les cookies expirés sont purgés au passage.
  String? headerFor(Uri uri, {DateTime? now}) {
    final DateTime at = now ?? DateTime.now();
    final int before = _cookies.length;
    _cookies.removeWhere((StoredCookie c) => c.isExpired(at));
    if (_cookies.length != before) _revision++;

    final String host = uri.host.toLowerCase();
    final String path = uri.path.isEmpty ? '/' : uri.path;
    final bool https = uri.scheme == 'https';
    final List<StoredCookie> matching = _cookies
        .where((StoredCookie c) =>
            (c.hostOnly ? host == c.domain : _domainMatches(host, c.domain)) &&
            _pathMatches(path, c.path) &&
            (!c.secure || https))
        .toList()
      // Les chemins les plus précis d'abord (ordre RFC 6265).
      ..sort((StoredCookie a, StoredCookie b) => b.path.length.compareTo(a.path.length));
    if (matching.isEmpty) return null;
    return matching.map((StoredCookie c) => '${c.name}=${c.value}').join('; ');
  }

  void clear() {
    if (_cookies.isEmpty) return;
    _cookies.clear();
    _revision++;
  }

  List<Map<String, Object?>> toJson() =>
      [for (final StoredCookie c in _cookies) c.toJson()];

  /// Debug uniquement : remplace chaque valeur par une valeur que le serveur
  /// refusera, pour simuler une expiration de session côté serveur.
  void debugCorruptValues() {
    if (!kDebugMode) return;
    for (int i = 0; i < _cookies.length; i++) {
      final StoredCookie c = _cookies[i];
      _cookies[i] = StoredCookie(
        name: c.name,
        value: 'INVALIDE${c.value.hashCode.abs()}',
        domain: c.domain,
        path: c.path,
        hostOnly: c.hostOnly,
        secure: c.secure,
        expiresAt: c.expiresAt,
      );
    }
    _revision++;
  }

  /// Analyse un en-tête `Set-Cookie`. Renvoie le cookie et s'il est déjà
  /// expiré (= demande de suppression), ou `null` si l'en-tête est rejeté.
  static (StoredCookie, bool)? _parse(String header, Uri uri, DateTime now) {
    final List<String> parts = header.split(';');
    final String pair = parts.first;
    final int eq = pair.indexOf('=');
    if (eq <= 0) return null;
    final String name = pair.substring(0, eq).trim();
    final String value = pair.substring(eq + 1).trim();
    if (name.isEmpty) return null;

    String? domainAttr;
    String? pathAttr;
    int? maxAge;
    DateTime? expires;
    bool secure = false;
    for (final String attribute in parts.skip(1)) {
      final int i = attribute.indexOf('=');
      final String key =
          (i < 0 ? attribute : attribute.substring(0, i)).trim().toLowerCase();
      final String attrValue = i < 0 ? '' : attribute.substring(i + 1).trim();
      switch (key) {
        case 'domain':
          domainAttr = attrValue;
        case 'path':
          pathAttr = attrValue;
        case 'max-age':
          maxAge = int.tryParse(attrValue);
        case 'expires':
          expires = _parseExpires(attrValue);
        case 'secure':
          secure = true;
      }
    }

    final String host = uri.host.toLowerCase();
    String domain = host;
    bool hostOnly = true;
    if (domainAttr != null && domainAttr.isNotEmpty) {
      final String d = (domainAttr.startsWith('.')
              ? domainAttr.substring(1)
              : domainAttr)
          .toLowerCase();
      if (!_domainMatches(host, d)) return null;
      domain = d;
      hostOnly = false;
    }

    final String path = (pathAttr != null && pathAttr.startsWith('/'))
        ? pathAttr
        : _defaultPath(uri.path);

    // Max-Age a priorité sur Expires (RFC 6265 §5.3).
    final DateTime? expiresAt = maxAge != null
        ? now.add(Duration(seconds: maxAge))
        : expires;
    final bool expired = expiresAt != null && !expiresAt.isAfter(now);

    return (
      StoredCookie(
        name: name,
        value: value,
        domain: domain,
        path: path,
        hostOnly: hostOnly,
        secure: secure,
        expiresAt: expiresAt,
      ),
      expired,
    );
  }

  /// Dates de cookies : on réutilise l'analyseur tolérant de dart:io
  /// (formats RFC 1123, RFC 850, Netscape…). Date illisible : ignorée.
  static DateTime? _parseExpires(String raw) {
    try {
      return Cookie.fromSetCookieValue('x=y; Expires=$raw').expires;
    } on Object {
      return null;
    }
  }

  static bool _sameContent(StoredCookie a, StoredCookie b) =>
      a.value == b.value &&
      a.expiresAt == b.expiresAt &&
      a.secure == b.secure &&
      a.hostOnly == b.hostOnly;

  static bool _domainMatches(String host, String domain) =>
      host == domain || host.endsWith('.$domain');

  static bool _pathMatches(String requestPath, String cookiePath) {
    if (requestPath == cookiePath) return true;
    if (!requestPath.startsWith(cookiePath)) return false;
    return cookiePath.endsWith('/') || requestPath[cookiePath.length] == '/';
  }

  /// Chemin par défaut (RFC 6265 §5.1.4) : le « répertoire » de la requête.
  static String _defaultPath(String requestPath) {
    if (requestPath.isEmpty || !requestPath.startsWith('/')) return '/';
    final int lastSlash = requestPath.lastIndexOf('/');
    return lastSlash <= 0 ? '/' : requestPath.substring(0, lastSlash);
  }
}
