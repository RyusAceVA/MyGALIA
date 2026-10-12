import 'package:flutter/widgets.dart';

/// Rayons d'arrondi standardisés pour toute l'application.
///
/// L'identité visuelle de MyGalia repose sur des angles **très arrondis**
/// (esthétique Material 3 Expressive / Planify). Centraliser ces valeurs
/// garantit une cohérence pixel-perfect entre widgets custom et thème global.
abstract final class AppRadius {
  AppRadius._();

  static const double xs = 8; // puces, petits badges
  static const double sm = 12; // champs compacts
  static const double md = 16; // inputs, boutons
  static const double lg = 24; // cartes
  static const double xl = 28; // bottom sheets, dialogs
  static const double pill = 999; // éléments « pilule » (chips, FAB étendu)

  static const BorderRadius input = BorderRadius.all(Radius.circular(md));
  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius sheet = BorderRadius.all(Radius.circular(xl));
}
