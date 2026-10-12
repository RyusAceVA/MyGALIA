import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/debug/redact.dart';

void main() {
  group('Redact.uri', () {
    test('masque les paramètres sensibles et garde les autres', () {
      final Uri uri = Uri.parse(
        'https://expernet.sc-form.net/GaliaEDC/Default.aspx'
        '?emailscco=prenom.nom%40exemple.fr&tokenscco=qOyVuTh7Y46XEewIkyUX2ie'
        '&tse=2&monoscco=1&localid=bgVkzwYuI429amhoTinp',
      );

      final String redacted = Redact.uri(uri);

      expect(redacted, isNot(contains('prenom.nom')));
      expect(redacted, isNot(contains('qOyVuTh7Y46XEewIkyUX2ie')));
      expect(redacted, isNot(contains('bgVkzwYuI429amhoTinp')));
      expect(redacted, contains('tse=2'));
      expect(redacted, contains('monoscco=1'));
    });

    test('masque le segment de session cookieless (S(…))', () {
      final Uri uri = Uri.parse(
        'https://expernet.sc-form.net/GaliaEDC/(S(mnimm4w4435bospfzebib1xz))'
        '/Eleve/MesNotes.aspx',
      );

      final String redacted = Redact.uri(uri);

      expect(redacted, isNot(contains('mnimm4w4435bospfzebib1xz')));
      expect(redacted, contains('/Eleve/MesNotes.aspx'));
    });

    test("masque l'e-mail de GetToken mais garde id/Jour/Mois/Annee", () {
      final Uri getToken = Uri.parse(
        'https://app-api.sc-form.net/api/v1/Account/GetToken'
        '?email=a.b%40c.fr&fonctionnalite=RedirectEDC',
      );
      final Uri planning = Uri.parse(
        'https://expernet.sc-form.net/PlanningWeb/PlanningJournalier/Stagiaire'
        '?id=1543&Jour=1&Mois=7&Annee=2026',
      );

      expect(Redact.uri(getToken), isNot(contains('a.b')));
      expect(Redact.uri(getToken), contains('fonctionnalite=RedirectEDC'));
      expect(Redact.uri(planning), contains('id=1543&Jour=1&Mois=7&Annee=2026'));
    });
  });

  test('URL imbriquée (ReturnUrl) : segment et paramètres sensibles masqués', () {
    final Uri withSegment = Uri.parse(
      'https://expernet.sc-form.net/GaliaEDC/Login.aspx'
      '?ReturnUrl=%2fGaliaEDC%2f(S(abcdefsecret))%2fEleve%2fMesNotes.aspx',
    );
    final Uri withToken = Uri.parse(
      'https://expernet.sc-form.net/GaliaEDC/Login.aspx?ReturnUrl='
      '${Uri.encodeQueryComponent('/GaliaEDC/Default.aspx?emailscco=a.b@c.fr&tokenscco=jetonsecret')}',
    );

    expect(Redact.uri(withSegment), isNot(contains('abcdefsecret')));
    expect(Redact.uri(withSegment), contains('(S(•••))'));
    expect(Redact.uri(withToken), isNot(contains('jetonsecret')));
    expect(Redact.uri(withToken), isNot(contains('a.b@c.fr')));
    expect(Redact.uri(withToken), contains('ReturnUrl=•••'));
  });

  test('Redact.location résout une redirection relative et la masque', () {
    final Uri base = Uri.parse('https://expernet.sc-form.net/GaliaEDC/Default.aspx');

    final String redacted =
        Redact.location('/GaliaEDC/(S(abcdef123))/Default.aspx', base);

    expect(redacted, 'https://expernet.sc-form.net/GaliaEDC/(S(•••))/Default.aspx');
  });

  test('Redact.cookieNames ne garde que les noms', () {
    final String names = Redact.cookieNames(const [
      '.ASPXAUTH=61C567ABCDEF; path=/; HttpOnly; SameSite=Lax',
      'ASP.NET_SessionId=whiaeq12345; path=/; HttpOnly',
    ]);

    expect(names, '.ASPXAUTH, ASP.NET_SessionId');
    expect(names, isNot(contains('61C567ABCDEF')));
    expect(names, isNot(contains('whiaeq12345')));
  });
}
