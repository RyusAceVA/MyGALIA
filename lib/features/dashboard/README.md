# feature: dashboard

Tableau de bord : synthèse emploi du temps + notes du jour.

Architecture en 3 couches (Clean-ish) :
- `domain/`  — entités & contrats (indépendant de Flutter/Dio/Hive).
- `data/`    — implémentation des repositories, sources distantes/locales, DTO.
- `presentation/` — écrans, widgets et contrôleurs Riverpod.
