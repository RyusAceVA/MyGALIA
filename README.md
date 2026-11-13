<p align="center">
  <img src=".github/assets/banner.png" alt="MyGalia : emploi du temps et notes SC Form dans une app Android" width="100%">
</p>

<h3 align="center">Client Android non officiel de l'espace élève SC Form / GaliaEDC</h3>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter&logoColor=white" alt="Flutter 3.44">
  <img src="https://img.shields.io/badge/Android-7%2B-3DDC84?logo=android&logoColor=white" alt="Android 7 et plus">
  <img src="https://img.shields.io/badge/Material%203-Expressive-6366F1" alt="Material 3 Expressive">
  <img src="https://img.shields.io/badge/version-1.0.0-8B5CF6" alt="Version 1.0.0">
</p>

<p align="center">
  <a href="#aperçu">Aperçu</a> •
  <a href="#fonctions">Fonctions</a> •
  <a href="#confidentialité-et-sécurité">Confidentialité</a> •
  <a href="#développement">Développement</a> •
  <a href="#publier-une-version">Publication</a>
</p>

---

Emploi du temps, notes, et un accueil qui résume la journée. Interface
Material 3 Expressive, écrite en Flutter.

> [!IMPORTANT]
> MyGalia n'est ni édité ni approuvé par SC Form. L'app lit les mêmes pages
> que le site officiel, avec vos identifiants, et ne les envoie nulle part
> ailleurs.

## Aperçu

| Accueil | Emploi du temps | Notes | Thème |
| :---: | :---: | :---: | :---: |
| <img src=".github/assets/demo_home.gif" alt="Actualisation de l'accueil avec l'indicateur à forme changeante" width="100%"> | <img src=".github/assets/demo_planning.gif" alt="Navigation de semaine en semaine dans l'emploi du temps" width="100%"> | <img src=".github/assets/demo_notes.gif" alt="Défilement des notes et changement de semestre" width="100%"> | <img src=".github/assets/demo_theme.gif" alt="Bascule entre thème clair et thème sombre" width="100%"> |
| Le cours en cours et sa progression | Semaine par semaine, jour par jour | Cursus, semestres et moyenne | Clair, sombre ou automatique |

### Les quatre écrans

Les captures suivent le thème de votre GitHub : clair ou sombre.

| Accueil | Emploi du temps | Notes | Paramètres |
| :---: | :---: | :---: | :---: |
| <picture><source media="(prefers-color-scheme: dark)" srcset=".github/assets/capture_sombre_home.png"><img src=".github/assets/capture_clair_home.png" alt="Écran d'accueil" width="100%"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset=".github/assets/capture_sombre_planning.png"><img src=".github/assets/capture_clair_planning.png" alt="Écran de l'emploi du temps" width="100%"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset=".github/assets/capture_sombre_notes.png"><img src=".github/assets/capture_clair_notes.png" alt="Écran des notes" width="100%"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset=".github/assets/capture_sombre_settings.png"><img src=".github/assets/capture_clair_settings.png" alt="Écran des paramètres" width="100%"></picture> |

### Couleurs du fond d'écran

Sur Android 12 et plus récent, MyGalia reprend la couleur que le système tire
de votre fond d'écran (Material You). Changez de fond : l'app change de teinte
à votre retour, en clair comme en sombre.

| En mouvement | Indigo (par défaut) | Fond terracotta | Fond vert |
| :---: | :---: | :---: | :---: |
| <img src=".github/assets/demo_couleurs.gif" alt="L'accueil passe de l'indigo au terracotta puis au vert" width="100%"> | <img src=".github/assets/palette_indigo.png" alt="Accueil en indigo" width="100%"> | <img src=".github/assets/palette_terracotta.png" alt="Accueil en terracotta" width="100%"> | <img src=".github/assets/palette_vert.png" alt="Accueil en vert" width="100%"> |

Même écran, trois fonds d'écran. L'animation enchaîne ces trois captures.
L'indigo reste la couleur de l'app avant Android 12.

### Clair et sombre

| Clair | Sombre |
| :---: | :---: |
| <img src=".github/assets/capture_clair_notes.png" alt="Écran des notes en thème clair" width="320"> | <img src=".github/assets/capture_sombre_notes.png" alt="Écran des notes en thème sombre" width="320"> |

Captures prises sur un Pixel 9 Pro. L'adresse e-mail et le nom des formateurs
y sont remplacés par des valeurs fictives.

---

## Fonctions

- **Accueil** : cours en cours ou à venir, planning du jour, dernières notes.
- **Emploi du temps** : semaine par semaine, saut de période de cours en
  période de cours (alternance), export de la semaine vers l'agenda (`.ics`).
- **Notes** : choix du cursus (classe) et du semestre, moyenne pondérée,
  meilleure et plus basse note. Les barèmes autres que /20 sont ramenés sur
  20 ; absences et dispenses sont affichées sans compter dans la moyenne.
- **Notifications** (à activer dans Paramètres) : nouvelle note publiée, et
  rappel le vendredi quand la semaine suivante comporte des cours à l'école.
- **Couleurs dynamiques** : la teinte de l'app suit votre fond d'écran
  (Android 12+), en thème clair, sombre ou automatique.
- **Hors ligne** : les dernières données valides restent consultables.

## Confidentialité et sécurité

- Identifiants, jeton et session : coffre chiffré (Keystore Android).
- Planning et notes en cache : boîte Hive chiffrée en AES, clé dans le coffre.
- Aucune sauvegarde cloud ni transfert d'appareil des données de l'app.
- Journaux de diagnostic actifs en debug seulement, secrets masqués.
- Seuls serveurs contactés : ceux de SC Form. Les polices sont embarquées.

## Respect du serveur de l'école

- Deux relances automatiques au plus, avec délai croissant.
- Une seule reconnexion à la fois, quel que soit le nombre d'écrans.
- Vérification en arrière-plan : quatre fois par jour au plus, et seulement
  si une notification est activée.

Le détail des garanties (session, cache, erreurs) est dans
[FIABILITE.md](FIABILITE.md).

## Développement

Prérequis : Flutter stable (3.44 ou plus récent) et le SDK Android 37.

```bash
flutter pub get
```

```bash
flutter analyze
```

```bash
flutter test
```

```bash
flutter run
```

Les tests n'appellent jamais le vrai portail : ils tournent contre un faux
serveur local (`test/support/fake_scform_server.dart`).

### Organisation du code

```
lib/
  core/        réseau, session, stockage, thème, widgets communs
  features/
    auth/            connexion, ouverture de la session école
    home/            accueil
    schedule/        emploi du temps, recherche de période, export agenda
    grades/          notes, cursus, semestres
    notifications/   nouvelles notes, rappel du vendredi, tâche de fond
    settings/        paramètres
```

Les paramètres du protocole (URL, noms des champs WebForms) sont regroupés
dans `lib/core/network/scform_config.dart`.

## Publier une version

1. Créer une clé de signature, une seule fois, et la garder hors du dépôt :

   ```bash
   keytool -genkey -v -keystore mygalia-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mygalia
   ```

2. Copier `android/key.properties.example` en `android/key.properties` et y
   renseigner le chemin de la clé et ses mots de passe. Ce fichier et les
   `.jks` sont ignorés par git.
3. Augmenter `version` dans `pubspec.yaml` (le nombre après `+` doit croître
   à chaque publication).
4. Construire :

   ```bash
   flutter build apk --release
   ```

Sans `android/key.properties`, la version release est signée avec la clé de
debug : pratique pour essayer, **à ne pas distribuer**. Perdre la clé de
signature empêche de publier des mises à jour installables par-dessus
l'ancienne version : sauvegardez-la ailleurs que sur ce PC.
