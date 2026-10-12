# Fiabilité du chargement — session, cache, relances

Ce document explique comment MyGalia charge l'emploi du temps et les notes
sans manipulation manuelle, et quelles règles respecter en modifiant le code.
Le protocole SC Form lui-même (URL, chaîne de redirections, postback) est
décrit dans les notes de rétro-ingénierie (`REVERSE_ENGINEERING.md`, hors
dépôt) ; les numéros de section (§2.2…) y renvoient.

## 1. Vue d'ensemble

```
Écran (ScheduleScreen / GradesScreen)
  │  pull-to-refresh, « Réessayer »          ← refresh() : TOUJOURS le réseau
  ▼
Contrôleur (ScheduleController / GradesController + mixin DataLoader)
  │  états : Chargement · Succès · Données en cache + bandeau · Erreur
  ▼
Repository (ScheduleRepository / GradesRepository)
  │  réseau d'abord ; n'écrit dans le cache QUE des données validées
  ▼
Source distante (ScheduleRemoteDataSource / GradesRemoteDataSource)
  │  parsing HTML (ScheduleParser / GradesParser)
  ▼
SchoolClient  ── point UNIQUE de détection d'une session invalide
  │  session refusée → SessionManager.renew() → rejeu UNE fois
  │  erreur transitoire → RetryPolicy (2 relances max)
  ▼
SessionManager ── reconnexion « single flight »
  │  AuthRepository (JWT) + EdcSessionBootstrap (chaîne de 302)
  ▼
Dio (dio_client.dart) : pas de redirection automatique, pas de cache HTTP
```

| Fichier | Rôle |
|---|---|
| `lib/core/network/scform_config.dart` | URL, en-têtes, chemins, noms WebForms (tout ce qui dépend du serveur) |
| `lib/core/network/dio_client.dart` | Client HTTP unique + journal réseau (debug) |
| `lib/core/network/failure.dart` | Erreurs typées |
| `lib/core/network/retry_policy.dart` | Relances automatiques |
| `lib/core/network/cookie_jar.dart` | Cookies d'UNE session école |
| `lib/core/session/session_manager.dart` | Ouverture, restauration, reconnexion de la session |
| `lib/core/session/school_client.dart` | Toutes les requêtes école + détection session invalide |
| `lib/core/session/session_validator.dart` | Reconnaissance redirection / page de login |
| `lib/core/storage/secure_storage_service.dart` | Coffre chiffré (identifiants, jeton, session) |
| `lib/core/storage/cache_store.dart` | Cache Hive des données valides |
| `lib/core/presentation/data_loader.dart` | Logique commune des contrôleurs d'écran |
| `lib/core/lifecycle/` | Rechargement au retour du réseau / au premier plan |
| `lib/core/debug/` | Journal masqué et outils de diagnostic (debug) |

## 2. Session

### 2.1 Deux étages

1. **Jeton API (JWT)** — `POST /Account/Login?DoubleAuth=true` (§2.1). Sert
   uniquement à obtenir le jeton de transition (`GetToken`). Il est conservé
   (avec sa date d'expiration) et réutilisé tant qu'il reste au moins 2 min.
2. **Session école** (`EdcSession`, §2.2) — obtenue par la chaîne de 302 de
   `GaliaEDC/Default.aspx`, suivie à la main : un cookie jar **neuf**, le
   cookie `.ASPXAUTH`, le segment cookieless `(S(…))` et le `pkEntite`.
   Le planning n'utilise que les cookies ; les notes utilisent cookies +
   segment.

### 2.2 Où sont les secrets

Uniquement dans le coffre chiffré (`SecureStorageService`,
`flutter_secure_storage` → EncryptedSharedPreferences, clé dans le Keystore
Android) :

| Clé | Contenu |
|---|---|
| `mygalia.credentials` | e-mail + mot de passe (reconnexion silencieuse) |
| `mygalia.api_token` | JWT + date d'expiration |
| `mygalia.edc_session` | cookies, segment, pkEntite, génération |

- `resetOnError: true` : un coffre indéchiffrable est réinitialisé au lieu
  d'échouer en boucle (l'utilisateur se reconnecte).
- `allowBackup="false"` + `res/xml/data_extraction_rules.xml` : rien n'est
  sauvegardé ni transféré (sinon le coffre restauré sans sa clé Keystore
  devient illisible).
- Les lectures du coffre ne lèvent jamais : illisible = vide.
- Rien de secret dans Hive, dans les journaux, ni dans `toString()`.

### 2.3 Détection d'une session invalide — un seul endroit

`SchoolClient._fetch` est le **seul** endroit qui juge une réponse de
l'école. Une session est invalide si :

| Signal | Pourquoi |
|---|---|
| statut 3xx | Dio ne suit jamais les redirections : un 302 vers le login est VU (sinon il arriverait en 200 avec le HTML du login) |
| 401 / 403 | refus explicite |
| page vide | observé lors d'expirations (§5.1) |
| page sans **repère de données** | page de login (champ mot de passe) ou page inattendue : erreur, maintenance, redirection JavaScript, session morte affichée autrement |

Repères de données (une vraie page en porte toujours au moins un, même
sans données) :
- planning : grille `Bouton_Info`, liens `PlanningJournalier` ou date du
  jour (`ScheduleParser.pageMarker`) — volontairement larges : rejeter un
  jour sans cours légitime casserait toute la semaine ;
- notes : sélecteur `DropDownLstPeriode` ou une note « /20 »
  (`GradesParser.pageMarker`).

Dans ces cas : `SessionManager.renew(staleGeneration)` puis **un seul** rejeu
de l'opération entière (pour les notes : GET **et** postback, car un
formulaire d'une session morte n'est jamais réutilisable). Encore refusée
après rejeu → `SessionFailure` (ou `DataFailure` pour une page vide).

### 2.4 Reconnexion « single flight »

- Une seule reconnexion à la fois : `renew()` partage le même `Future` entre
  toutes les requêtes qui échouent en même temps.
- Chaque session porte une **génération**. Une requête qui échoue avec une
  session déjà remplacée rejoue directement avec la nouvelle, sans
  reconnexion supplémentaire.
- La reconnexion **repart de zéro** : ancienne session et cookies jetés
  avant la poignée de main.
- Déroulé : jeton API valable ? sinon `Login` → `GetToken` → chaîne de 302.
  Si `GetToken` refuse le jeton (401/403) : un nouveau `Login`, puis une
  dernière tentative.
- `reset(signedIn: …)` (déconnexion, nouvelle connexion) incrémente une
  **époque**, revérifiée avant chaque étape d'une reconnexion : une
  reconnexion à cheval ne peut plus rien enregistrer, effacer ni envoyer
  (jamais l'ancien mot de passe). Après une déconnexion, plus aucune
  reconnexion n'est tentée : les chargements encore en vol sont annulés
  silencieusement, et les repositories n'écrivent pas dans le cache si
  l'époque a changé pendant le chargement.
- Le `Future` de reconnexion est libéré dans un `finally` : rien ne reste
  bloqué, la reconnexion suivante repart proprement.

### 2.5 Cookies (`CookieJar`)

Un cookie est identifié par (nom, domaine, chemin) : une nouvelle valeur
**remplace** l'ancienne (jamais de doublon). `Max-Age<=0` / `Expires` passé
le suppriment ; les cookies expirés sont purgés avant chaque envoi ; un
`Domain` étranger est refusé ; un jar par session. Les `Set-Cookie` reçus en
cours de route (ex. `ASP.NET_SessionId` de PlanningWeb) sont persistés si la
session est toujours la session courante.

### 2.6 Qui déconnecte l'utilisateur ?

**Seulement** des identifiants refusés par SC Form (400/401/403 au login)
ou absents du coffre. `SessionManager` purge alors le coffre et émet
`sessionLost` ; `AuthController` purge le reste et affiche l'écran de
connexion avec le message. Réseau, serveur, session école, page illisible :
jamais de déconnexion forcée, seulement une erreur avec « Réessayer ».

## 3. Cache

- Hive, boîte `cache_box`. Une entrée = `{v: version, savedAt, data}`.
- Clés : `planning:AAAA-M-J` (lundi de la semaine), `notes:courant` ou
  `notes:<valeur du semestre>`.
- **Écriture uniquement après succès complet** : semaine entière parsée,
  page de notes reconnue. Une erreur (session, réseau, page vide, corrompue
  ou de connexion) laisse le dernier cache valide intact.
- **Lecture défensive** : JSON corrompu, structure inattendue ou ancienne
  version (`CacheStore.schemaVersion`) → entrée supprimée, traitée comme
  absente. Changer la structure d'un modèle ⇒ incrémenter `schemaVersion`.
- **Pas de cache HTTP** (Dio n'en a pas, toutes les URL sont en HTTPS) :
  chaque chargement réseau part réellement sur le réseau.
- Rôle du cache : affichage immédiat et secours hors ligne, avec « Mis à
  jour le … » et un bandeau si le rafraîchissement a échoué.
- Démarrage : une boîte Hive illisible est recréée vide (`main.dart`).

## 4. États et rafraîchissement (`DataLoader`)

| État | Affichage |
|---|---|
| `DataLoading` | indicateur central (rien à montrer) |
| `DataSuccess` | données fraîches + « Mis à jour … » |
| `DataCached` | dernières données valides ; si `failure` : bandeau « Rafraîchissement impossible » + Réessayer |
| `DataError` | erreur typée expliquée + Réessayer |

Règles :
- `refresh()` (Réessayer, pull-to-refresh) interroge **toujours** le réseau.
  Ce n'est pas un état réémis : c'est un nouvel appel. Si un chargement est
  déjà en cours, son `Future` est réutilisé (pas de doublon serveur).
- Chaque chargement publie toujours un état final, même sur exception
  inattendue, et libère sa place (`whenComplete`).
- Riverpod 2.6 réutilise l'instance du contrôleur quand il reconstruit le
  provider : chaque `build` ouvre une **époque**, et le résultat d'une
  requête antérieure n'est jamais publié après.
- Destruction du provider (semaine quittée, déconnexion) = requête annulée
  (`CancelToken`) ; une annulation n'est jamais affichée comme erreur.
- À l'ouverture : cache de moins de 5 min affiché sans requête ; sinon cache
  affiché pendant le chargement réseau.
- Un contrôleur par semaine et par semestre : jamais de mélange de données.

Erreurs typées (`failure.dart`) : `NetworkFailure` (pas de réseau, délai
dépassé, connexion interrompue), `ServerFailure` (5xx transitoire, 4xx),
`SessionFailure`, `InvalidCredentialsFailure`, `SignedOutFailure`,
`DataFailure` (données illisibles), `CacheFailure`, `CancelledFailure`
(jamais affichée), `UnknownFailure`. La cause technique est conservée pour
le diagnostic, le message est affichable tel quel.

## 5. Relances automatiques (`RetryPolicy`) et délais

| Paramètre | Valeur |
|---|---|
| Délai de connexion | 10 s |
| Délai d'envoi | 15 s |
| Délai de réception | 20 s |
| Relances | 2 au maximum, après 1 s puis 3 s |

- Relancé : timeout, 5xx, coupure réseau (`Failure.isTransient`).
- Jamais relancé : identifiants refusés, 4xx, session, données illisibles,
  annulation — ni quand l'appareil se sait hors ligne.
- **Un seul niveau de relance** par unité de travail : connexion API ;
  « jeton de transition + chaîne de 302 » (relancés ensemble, le jeton est à
  usage unique) ; chaque requête de données. Ne jamais imbriquer deux
  `RetryPolicy`.
- Le planning est chargé jour par jour **en séquence** ; la première erreur
  interrompt la semaine (pas de semaine partielle, pas de rafale).

## 6. Rechargements automatiques

`AppLifecycleWatcher` (monté avec l'écran principal) émet un signal au
retour au premier plan et au retour du réseau (`connectivity_plus`). Chaque
écran ne recharge que si son dernier essai a échoué **ou** si ses données
ont plus de 30 min, et au plus une fois par fenêtre de 20 s (anti-rafale).
Seuils dans `AppConstants`.

## 7. Déconnexion

`AuthController.signOut()` (et toute nouvelle connexion) : `reset()` de la
session (cookies en mémoire oubliés, opérations en cours neutralisées),
coffre vidé (identifiants, jeton, session école), cache Hive vidé. L'écran
principal est détruit, ses requêtes annulées. Une reconnexion refait une
poignée de main complète.

## 8. Diagnostic (build debug uniquement)

- **Journal** (`AppLog`) : étapes de session, codes HTTP, redirections, noms
  des cookies reçus, décisions cache/réseau, relances. Visible dans logcat
  (`flutter`) et dans l'écran « Diagnostic (debug) » du menu du compte.
- **Jamais journalisés** : corps de requêtes/réponses, en-têtes `Cookie`,
  `Set-Cookie` (seulement les noms) et `Authorization`, mot de passe,
  jetons. Dans les URL : `email`, `emailscco`, `tokenscco`, `token`,
  `password`, `localid` et le segment `(S(…))` sont masqués (`Redact`),
  y compris à l'intérieur d'une URL passée en paramètre (`ReturnUrl`).
- **Invalider la session école** : cookies et segment faussés ⇒ la requête
  suivante doit se réparer seule. **Invalider aussi le jeton API** : exerce
  en plus la reconnexion API.
- Tout est sous `kDebugMode` (constante) : absent et retiré à la compilation
  en release.

## 9. Tests

```bash
flutter test
```

`test/support/fake_scform_server.dart` est un vrai serveur HTTP local
(équivalent MockWebServer) qui reproduit le protocole : JWT, jeton de
transition à usage unique, chaîne de 302 avec `.ASPXAUTH` et `(S(…))`,
planning, notes avec validation du postback, et trois façons d'expirer une
session (200 + login, 302, 401). `test/scenarios/phase3_scenarios_test.dart`
reprend les scénarios de vérification de bout en bout ; les autres dossiers
testent chaque brique (session, cache, parsing, relances, écrans, journaux
sans secret).

## 10. Modifier sans casser

Si SC Form change :
- URL, en-têtes, chemins, nom du sélecteur de semestre : `ScFormConfig`.
- Format des séances : `ScheduleParser` (regex d'horaires, mapping des
  lignes, repli si la classe `Bouton_Info` disparaît).
- Format des notes : `GradesParser._gradeBlock` (regex d'origine §4.1,
  segments « tempérés » pour qu'une note incomplète ne fusionne jamais
  avec la suivante).
- Reconnaissance du login : `SessionValidator` ; repères de pages de
  données : `ScheduleParser.pageMarker`, `GradesParser.pageMarker`
  (passés à `getPage(marker: …)`).
- Le journal debug montre la requête et la raison exacte d'un refus.

Règles à ne pas enfreindre :
1. Toute requête vers l'école passe par `SchoolClient.run` (jamais Dio en
   direct) : c'est là que la session est vérifiée et réparée.
2. Ne jamais réactiver `followRedirects` ni restreindre `validateStatus`.
3. N'écrire dans le cache qu'après un parsing validé et complet.
4. Toute page de données a un repère (`marker`) ; un parseur qui ne
   reconnaît pas la page doit lever `DataFailure`, jamais renvoyer une
   liste vide « par défaut » (sauf page valide sans données).
5. Une seule couche de relance par unité de travail ; relancer seulement
   les erreurs `isTransient`.
6. Ne jamais journaliser un corps, un cookie, un jeton ni un mot de passe ;
   passer les URL par `Redact.uri`.
7. Un contrôleur d'écran doit publier un état final dans tous les cas et
   ne jamais conserver un `Future` terminé comme « en cours ».
8. Seuls des identifiants refusés ou absents déconnectent l'utilisateur.

## 11. Vérification sur téléphone

Build debug branché à Android Studio (journal : onglet Logcat, filtre
`MyGalia`, ou menu du compte → « Diagnostic (debug) »).

| Test | Manipulation | Résultat attendu |
|---|---|---|
| Mode avion puis Réessayer | Données affichées, activer le mode avion, tirer l'écran | Bandeau « Rafraîchissement impossible — Pas de connexion Internet », données conservées ; sans données : écran « Pas de connexion » + Réessayer. Chaque appui relance (journal : nouvelle requête), aucune relance automatique hors ligne |
| Retour du réseau | Désactiver le mode avion | Rechargement automatique en quelques secondes, bandeau disparu |
| Arrière-plan plusieurs heures | Quitter l'app (sans la fermer), revenir après 1 h ou plus | Données anciennes affichées puis rechargées seules ; session expirée réparée silencieusement (journal : « session refusée … reconnexion puis rejeu unique ») |
| App tuée puis relancée | Fermer depuis les apps récentes, relancer | Pas d'écran de connexion ; cache affiché tout de suite puis données fraîches |
| Rotation de l'écran | Tourner le téléphone pendant un chargement | Aucun rechargement en double, aucun écran bloqué |
| « Invalider la session » | Diagnostic → Invalider la session école, revenir, tirer l'écran | Données rechargées sans action ; journal : refus (302 ou page de login) → reconnexion → rejeu réussi. Recommencer avec « Invalider aussi le jeton API » |
| Mauvais mot de passe | Se déconnecter, se reconnecter avec un mot de passe faux | Message clair, une seule tentative ; avec le bon mot de passe : connexion normale |
| Mot de passe changé sur le portail | Changer le mot de passe sur SC Form, attendre l'expiration ou utiliser « Invalider aussi le jeton API » | Retour à l'écran de connexion avec le message du serveur |
| Serveur lent | Réseau très faible (ex. 2G / mode développeur « réseau lent ») | Indicateur de chargement, puis données ; au-delà de 20 s sans réponse : jusqu'à 2 relances (1 s puis 3 s), puis « Serveur trop lent » + Réessayer, jamais d'écran figé |
