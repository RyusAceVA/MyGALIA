import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mygalia/core/network/scform_config.dart';

/// Façon dont le serveur signale une session école expirée.
enum ExpiryMode {
  loginPage200,
  redirect302,
  unauthorized401,
  emptyBody200,

  /// Page d'erreur HTML en 200, sans formulaire de connexion.
  errorPage200,
}

/// Faux serveur SC Form : un VRAI serveur HTTP local (équivalent de
/// MockWebServer) qui reproduit le protocole de REVERSE_ENGINEERING.md :
/// API JWT, jeton de transition, chaîne de 302 GaliaEDC posant `.ASPXAUTH`
/// et le segment `(S(…))`, planning journalier, notes avec postback WebForms.
class FakeScFormServer {
  late final HttpServer _server;

  // --- Compte -----------------------------------------------------------------
  String email = 'prenom.nom@exemple.fr';
  String password = 'mot-de-passe-tres-secret';
  final String planningId = '1543';

  // --- Comportements programmables --------------------------------------------
  ExpiryMode expiryMode = ExpiryMode.redirect302;

  /// Les [planningDelayCount] prochaines requêtes de planning attendent
  /// [planningDelay] avant de répondre (simulation de timeout).
  Duration planningDelay = Duration.zero;
  int planningDelayCount = 0;

  /// Les N prochaines requêtes de planning répondent 503.
  int planningServerErrors = 0;

  /// Corps servi à la place du planning (page vide, contenu corrompu…).
  String? planningBodyOverride;

  /// Réponse imposée à la prochaine connexion API (statut, corps), à la
  /// place du traitement normal : pare-feu, limite de débit…
  (int, String)? loginOverride;

  /// Retard de GetToken : élargit la fenêtre de concurrence des tests.
  Duration getTokenDelay = Duration.zero;

  /// Expire la session école juste après le prochain GET des notes (donc
  /// avant le postback qui suit).
  bool expireAfterNextNotesGet = false;

  // --- Compteurs ----------------------------------------------------------------
  int loginCalls = 0;
  int getTokenCalls = 0;
  int edcEntryCalls = 0;
  int planningCalls = 0;
  int notesGetCalls = 0;
  int notesPostCalls = 0;

  // --- État interne -------------------------------------------------------------
  int _counter = 0;
  final Set<String> _validJwts = <String>{};
  final Set<String> _transitionTokens = <String>{};
  final Map<String, String> _pendingSegments = <String, String>{};
  String? _validAuth;
  String? _validSegment;

  /// Secrets émis pendant le test (pour vérifier qu'aucun n'est journalisé).
  final Set<String> issuedSecrets = <String>{};

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  ScFormConfig get config => ScFormConfig(
        apiBaseUrl: '$baseUrl/api/v1',
        schoolBaseUrl: baseUrl,
        edcLocalId: 'localidtest',
      );

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() => _server.close(force: true);

  /// Expire la session école côté serveur (cookie et segment refusés).
  void expireSchoolSession() {
    _validAuth = null;
    _validSegment = null;
  }

  /// Expire les jetons API : la prochaine reconnexion devra se reconnecter
  /// à l'API (et donc présenter des identifiants valides).
  void expireApiTokens() => _validJwts.clear();

  // ---------------------------------------------------------------------------

  Future<void> _handle(HttpRequest request) async {
    try {
      await _route(request);
    } on Object {
      try {
        request.response.statusCode = 500;
      } on Object {
        // En-têtes déjà envoyés.
      }
    } finally {
      try {
        await request.response.close();
      } on Object {
        // Client parti (timeout côté client) : sans importance.
      }
    }
  }

  Future<void> _route(HttpRequest req) async {
    final String path = req.uri.path;
    if (req.method == 'POST' && path == '/api/v1/Account/Login') {
      return _login(req);
    }
    if (req.method == 'GET' && path == '/api/v1/Account/GetToken') {
      return _getToken(req);
    }
    if (req.method == 'GET' && path == '/GaliaEDC/Default.aspx') {
      return _edcEntry(req);
    }
    if (path == '/GaliaEDC/Login.aspx') {
      return _html(req.response, loginPageHtml);
    }
    final Match? edcPage =
        RegExp(r'^/GaliaEDC/(\(S\([^)]+\)\))(/.*)$').firstMatch(path);
    if (edcPage != null) {
      return _edcPage(req, edcPage.group(1)!, edcPage.group(2)!);
    }
    if (req.method == 'GET' && path == ScFormConfig.planningJournalierPath) {
      return _planning(req);
    }
    req.response.statusCode = 404;
  }

  Future<void> _login(HttpRequest req) async {
    loginCalls++;
    final (int, String)? forced = loginOverride;
    if (forced != null) {
      req.response.statusCode = forced.$1;
      return _html(req.response, forced.$2);
    }
    final String body = await utf8.decodeStream(req);
    final Map<String, Object?> json =
        (jsonDecode(body) as Map<Object?, Object?>).cast<String, Object?>();
    final bool headerOk = req.headers.value('logiciel') == 'SC-Connect';
    if (!headerOk || json['email'] != email || json['password'] != password) {
      req.response.statusCode = 401;
      return _json(req.response, {'message': 'Identifiant ou mot de passe incorrect'});
    }
    final String jwt = 'eyJwt${++_counter}secret';
    _validJwts.add(jwt);
    issuedSecrets.add(jwt);
    _json(req.response, {
      'accesToken': jwt,
      'expires': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      'refreshToken': 'refresh$_counter',
    });
  }

  Future<void> _getToken(HttpRequest req) async {
    getTokenCalls++;
    if (getTokenDelay > Duration.zero) await Future<void>.delayed(getTokenDelay);
    final String? authorization = req.headers.value('authorization');
    final String? jwt = authorization != null && authorization.startsWith('Bearer ')
        ? authorization.substring(7)
        : null;
    final Map<String, String> q = req.uri.queryParameters;
    if (jwt == null ||
        !_validJwts.contains(jwt) ||
        q['email'] != email ||
        q['fonctionnalite'] != 'RedirectEDC') {
      req.response.statusCode = 401;
      return;
    }
    final String token = 'transition${++_counter}secret';
    _transitionTokens.add(token);
    issuedSecrets.add(token);
    _json(req.response, {'token': token});
  }

  void _edcEntry(HttpRequest req) {
    edcEntryCalls++;
    final Map<String, String> q = req.uri.queryParameters;
    final String? token = q['tokenscco'];
    // Le jeton de transition est à usage unique.
    if (token == null ||
        !_transitionTokens.remove(token) ||
        q['emailscco'] != email ||
        q['tse'] != '2' ||
        q['monoscco'] != '1') {
      return _redirect(req.response, '/GaliaEDC/Login.aspx');
    }
    final String id = 'sess${++_counter}secretid';
    final String segment = '(S($id))';
    _pendingSegments[segment] = 'AUTH${_counter}SECRETVALUE';
    issuedSecrets
      ..add(id)
      ..add(_pendingSegments[segment]!);
    _redirect(req.response, '/GaliaEDC/$segment/Default.aspx');
  }

  Future<void> _edcPage(HttpRequest req, String segment, String rest) async {
    final HttpResponse res = req.response;
    if (rest == '/Default.aspx') {
      final String? auth = _pendingSegments.remove(segment);
      if (auth == null) return _redirect(res, '/GaliaEDC/Login.aspx');
      _validAuth = auth;
      _validSegment = segment;
      final String sessionId = 'SIDSECRET$_counter';
      issuedSecrets.add(sessionId);
      res.headers
        ..add('set-cookie', '.ASPXAUTH=$auth; path=/; HttpOnly; SameSite=Lax')
        ..add('set-cookie', 'ASP.NET_SessionId=$sessionId; path=/; HttpOnly');
      return _redirect(res, '/GaliaEDC/$segment/Accueil/Stagiaire.aspx');
    }
    // Les compteurs comptent les TENTATIVES, acceptées ou non.
    if (rest == ScFormConfig.mesNotesPath && req.method == 'GET') notesGetCalls++;
    if (rest == ScFormConfig.mesNotesPath && req.method == 'POST') notesPostCalls++;
    if (!_authorized(req) || segment != _validSegment) return _expired(res);
    if (rest == '/Accueil/Stagiaire.aspx') {
      return _html(res, stagiaireHtml(planningId));
    }
    if (rest == ScFormConfig.mesNotesPath && req.method == 'GET') {
      if (expireAfterNextNotesGet) {
        expireAfterNextNotesGet = false;
        expireSchoolSession();
      }
      return _html(res, notesPageHtml(period: '30'));
    }
    if (rest == ScFormConfig.mesNotesPath && req.method == 'POST') {
      final Map<String, String> form =
          Uri.splitQueryString(await utf8.decodeStream(req));
      final bool valid =
          form['__EVENTTARGET'] == ScFormConfig.periodSelectName &&
              form['__VIEWSTATE'] == viewState &&
              form['__EVENTVALIDATION'] == eventValidation &&
              form[r'ctl00$MainContent$DropDownLstClasse'] == '17' &&
              form[r'ctl00$MainContent$RadioButtonAffichage'] == '0' &&
              !form.containsKey(r'ctl00$MainContent$BtnValider');
      final String? period = form[ScFormConfig.periodSelectName];
      if (!valid || (period != '30' && period != '31')) {
        res.statusCode = 400; // « Invalid postback or callback argument »
        return;
      }
      return _html(res, notesPageHtml(period: period!));
    }
    res.statusCode = 404;
  }

  Future<void> _planning(HttpRequest req) async {
    planningCalls++;
    if (planningDelayCount > 0) {
      planningDelayCount--;
      await Future<void>.delayed(planningDelay);
    }
    final HttpResponse res = req.response;
    if (planningServerErrors > 0) {
      planningServerErrors--;
      res.statusCode = 503;
      return;
    }
    if (!_authorized(req)) return _expired(res);
    final Map<String, String> q = req.uri.queryParameters;
    if (q['id'] != planningId) {
      res.statusCode = 404;
      return;
    }
    final String planningSession = 'PLANSECRET$_counter';
    issuedSecrets.add(planningSession);
    res.headers.add('set-cookie', 'ASP.NET_SessionId=$planningSession; path=/; HttpOnly');
    final String? override = planningBodyOverride;
    if (override != null) return _html(res, override);
    _html(
      res,
      planningDayHtml(DateTime(
        int.parse(q['Annee']!),
        int.parse(q['Mois']!),
        int.parse(q['Jour']!),
      )),
    );
  }

  bool _authorized(HttpRequest req) {
    final String cookies = req.headers.value('cookie') ?? '';
    final String? auth = cookies
        .split(';')
        .map((String c) => c.trim())
        .where((String c) => c.startsWith('.ASPXAUTH='))
        .map((String c) => c.substring('.ASPXAUTH='.length))
        .firstOrNull;
    return auth != null && auth == _validAuth;
  }

  void _expired(HttpResponse res) {
    switch (expiryMode) {
      case ExpiryMode.loginPage200:
        _html(res, loginPageHtml);
      case ExpiryMode.redirect302:
        _redirect(res, '/GaliaEDC/Login.aspx?ReturnUrl=%2fGaliaEDC');
      case ExpiryMode.unauthorized401:
        res.statusCode = 401;
      case ExpiryMode.emptyBody200:
        _html(res, '');
      case ExpiryMode.errorPage200:
        _html(res, errorPageHtml);
    }
  }

  static void _redirect(HttpResponse res, String location) {
    res
      ..statusCode = 302
      ..headers.set('location', location);
  }

  static void _html(HttpResponse res, String body) {
    res.headers.contentType = ContentType.html;
    res.write(body);
  }

  static void _json(HttpResponse res, Object json) {
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(json));
  }

  // --- Pages HTML (structure observée dans les notes de rétro-ingénierie) ----

  static const String viewState = 'FlxkXYAP8PVSG125o+rkYcl29ZbpzE1/NUHZo0XtV+oR5QJ78==';
  static const String eventValidation = 'u3jgzWmqp+Ee4XtBvMGWh3Og0+dOhH3jo9pNK==';

  static const String loginPageHtml = '''
<html><body><form method="post" action="Login.aspx">
<input type="text" name="ctl00\$Identifiant" />
<input type="password" name="ctl00\$MotDePasse" />
<input type="submit" value="Connexion" />
</form></body></html>''';

  /// Page d'erreur générique, sans repère de données ni formulaire de login.
  static const String errorPageHtml = '''
<html><body><h1>Une erreur est survenue</h1>
<p>Votre session a expiré. <a href="/GaliaEDC/Default.aspx">Retour</a></p>
</body></html>''';

  static String stagiaireHtml(String planningId) => '''
<html><body>
<a href="/PlanningWeb/PlanningJournalier/Stagiaire?id=$planningId&amp;Jour=1&amp;Mois=7&amp;Annee=2026">Mon planning</a>
<script>var G_PkEntitePlanning = '$planningId';</script>
</body></html>''';

  /// Une séance le matin (rendue deux fois, comme avec un rowspan) et un
  /// créneau vide.
  static String planningDayHtml(DateTime day) {
    final String d = day.day.toString().padLeft(2, '0');
    final String m = day.month.toString().padLeft(2, '0');
    final String title = 'Le $d/$m/${day.year} de 08:30 &#224; 12:00 (03h30)&#13;&#10;'
        'TSRS1&#13;&#10;DEVELOPPEMENT WEB&#13;&#10;'
        'DEWOLF GIAMMATTEI Fran&#231;ois&#13;&#10;PITON FOURNAISE';
    return '''
<html><body><table class="Grille"><tr>
<td rowspan="2"><div class="Bouton_Info" title="$title">DEV WEB</div></td>
<td><div class="Bouton_Info" title="$title">DEV WEB</div></td>
<td><div class="Bouton_Info" title=""></div></td>
</tr></table></body></html>''';
  }

  static String notesPageHtml({required String period}) {
    final String grades = period == '31'
        ? _gradeRow('15,5', '2,00', 'Anglais technique', 'REF ANG', '10/10/2025', 'Oral')
        : _gradeRow('12.5', '1,00', 'Sensibilisation ITIL', 'REF ITIL', '19/09/2025', 'Devoir surveillé') +
            _gradeRow('8', '1,00', 'R&#233;seaux', 'REF RES', '03/06/2025', 'TP not&#233;');
    String selected(String value) => value == period ? 'selected="selected" ' : '';
    return '''
<html><body><form method="post" action="./MesNotes.aspx" id="form1">
<input type="hidden" name="__EVENTTARGET" id="__EVENTTARGET" value="" />
<input type="hidden" name="__EVENTARGUMENT" id="__EVENTARGUMENT" value="" />
<input type="hidden" name="__VIEWSTATE" id="__VIEWSTATE" value="$viewState" />
<input type="hidden" name="__VIEWSTATEGENERATOR" value="472C7C7B" />
<input type="hidden" name="__EVENTVALIDATION" value="$eventValidation" />
<input type="hidden" name="ctl00\$Menu\$HF_EMAIL_COMPTE" value="prenom.nom@exemple.fr" />
<select name="ctl00\$MainContent\$DropDownLstClasse"><option selected="selected" value="17">TSRS1</option></select>
<select name="ctl00\$MainContent\$DropDownLstPeriode" onchange="javascript:setTimeout('__doPostBack(\\'ctl00\$MainContent\$DropDownLstPeriode\\',\\'\\')', 0)">
  <option ${selected('31')}value="31">SEMESTRE 2 (du 29/09/2025 au 11/09/2026)</option>
  <option ${selected('30')}value="30">SEMESTRE 1 (du 16/09/2024 au 19/09/2025)</option>
</select>
<input type="radio" name="ctl00\$MainContent\$RadioButtonAffichage" value="0" checked="checked" />
<input type="radio" name="ctl00\$MainContent\$RadioButtonAffichage" value="1" />
<input type="submit" name="ctl00\$MainContent\$BtnValider" value="Valider" />
<table>$grades</table>
</form></body></html>''';
  }

  static String _gradeRow(
    String value,
    String coeff,
    String subject,
    String ref,
    String date,
    String type,
  ) =>
      '''
<tr><td><span style="font-weight:bold;font-size:13px;">$value</span> <span>/20</span>
<span style="color:DimGray;font-size:9px;">coeff. $coeff</span>
</td><td style="padding-left:3px;">
  <span style="font-size:13px;">$subject</span>
  <span style="font-size:11px;">$ref          du $date</span>
  <span style="font-size:9px;">$type</span>
</td></tr>''';
}
