import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/network/cookie_jar.dart';

void main() {
  final Uri edc = Uri.parse(
    'https://expernet.sc-form.net/GaliaEDC/(S(abc))/Default.aspx',
  );
  final Uri planning = Uri.parse(
    'https://expernet.sc-form.net/PlanningWeb/PlanningJournalier/Stagiaire?id=1',
  );
  final DateTime now = DateTime.utc(2026, 10, 12, 12);

  test('accumule les cookies de la chaîne EDC et les renvoie sur tout le domaine', () {
    final CookieJar jar = CookieJar()
      ..saveFromResponse(edc, const [
        '.ASPXAUTH=61C567; path=/; HttpOnly; SameSite=Lax',
        'ASP.NET_SessionId=whiaeq; path=/; HttpOnly',
      ], now: now);

    final String? header = jar.headerFor(planning, now: now);

    expect(header, contains('.ASPXAUTH=61C567'));
    expect(header, contains('ASP.NET_SessionId=whiaeq'));
  });

  test('une nouvelle valeur remplace l\'ancienne (pas de doublon)', () {
    final CookieJar jar = CookieJar()
      ..saveFromResponse(edc, const ['ASP.NET_SessionId=ancien; path=/'], now: now)
      ..saveFromResponse(planning, const ['ASP.NET_SessionId=nouveau; path=/'], now: now);

    expect(jar.cookies, hasLength(1));
    expect(jar.headerFor(planning, now: now), 'ASP.NET_SessionId=nouveau');
  });

  test('chemins différents : deux cookies distincts, chacun sur son chemin', () {
    final CookieJar jar = CookieJar()
      ..saveFromResponse(edc, const [
        'pref=racine; path=/',
        'pref=planning; path=/PlanningWeb',
      ], now: now);

    expect(jar.cookies, hasLength(2));
    // Le plus précis d'abord sur /PlanningWeb, seul le cookie racine ailleurs.
    expect(jar.headerFor(planning, now: now), 'pref=planning; pref=racine');
    expect(jar.headerFor(edc, now: now), 'pref=racine');
  });

  test('Max-Age=0 ou Expires passé supprime le cookie', () {
    final CookieJar jar = CookieJar()
      ..saveFromResponse(edc, const ['.ASPXAUTH=abc; path=/'], now: now)
      ..saveFromResponse(edc, const ['.ASPXAUTH=; path=/; Max-Age=0'], now: now);
    expect(jar.isEmpty, isTrue);

    jar
      ..saveFromResponse(edc, const ['x=1; path=/'], now: now)
      ..saveFromResponse(edc, const [
        'x=; path=/; expires=Thu, 01-Jan-1970 00:00:00 GMT',
      ], now: now);
    expect(jar.isEmpty, isTrue);
  });

  test('un cookie expiré entre-temps n\'est plus envoyé et il est purgé', () {
    final CookieJar jar = CookieJar()
      ..saveFromResponse(edc, const ['court=1; path=/; Max-Age=60'], now: now);

    expect(jar.headerFor(edc, now: now), 'court=1');
    expect(jar.headerFor(edc, now: now.add(const Duration(minutes: 2))), isNull);
    expect(jar.isEmpty, isTrue);
  });

  test('un Domain étranger à l\'hôte est refusé', () {
    final CookieJar jar = CookieJar()
      ..saveFromResponse(edc, const ['pirate=1; domain=evil.example; path=/'], now: now);

    expect(jar.isEmpty, isTrue);
  });

  test('un cookie sans Domain n\'est pas envoyé à un autre hôte', () {
    final CookieJar jar = CookieJar()
      ..saveFromResponse(edc, const ['.ASPXAUTH=abc; path=/'], now: now);

    expect(
      jar.headerFor(Uri.parse('https://app-api.sc-form.net/api/v1/x'), now: now),
      isNull,
    );
  });

  test('un Set-Cookie identique ne marque pas le jar comme modifié', () {
    final CookieJar jar = CookieJar()
      ..saveFromResponse(edc, const ['a=1; path=/'], now: now);
    final int revision = jar.revision;

    jar.saveFromResponse(edc, const ['a=1; path=/'], now: now);

    expect(jar.revision, revision);
  });

  test('aller-retour JSON sans perte', () {
    final CookieJar jar = CookieJar()
      ..saveFromResponse(edc, const [
        '.ASPXAUTH=61C567; path=/; HttpOnly',
        'tmp=1; path=/; Max-Age=3600; Secure',
      ], now: now);

    final CookieJar copy = CookieJar.fromJson(jar.toJson());

    expect(copy.headerFor(planning, now: now), jar.headerFor(planning, now: now));
  });
}
