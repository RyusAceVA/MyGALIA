import 'package:mygalia/core/network/failure.dart';

/// État explicite d'un écran de données (planning, notes).
///
/// Chaque changement crée une NOUVELLE instance : l'UI est toujours
/// notifiée, il n'y a jamais d'état « identique » qui serait ignoré.
sealed class DataState<T> {
  const DataState();

  /// Données affichables (fraîches ou en cache), si elles existent.
  T? get data => null;

  /// Date des données affichées.
  DateTime? get updatedAt => null;

  /// Un chargement réseau est en cours (données éventuelles affichées).
  bool get isRefreshing => false;

  /// Erreur à signaler : écran d'erreur ou bandeau au-dessus des données.
  Failure? get failure => null;
}

/// Chargement, sans rien à afficher pour l'instant.
final class DataLoading<T> extends DataState<T> {
  const DataLoading();
}

/// Données fraîches, obtenues du réseau.
final class DataSuccess<T> extends DataState<T> {
  const DataSuccess(this.data, this.updatedAt, {this.isRefreshing = false});

  @override
  final T data;

  @override
  final DateTime updatedAt;

  @override
  final bool isRefreshing;
}

/// Dernières données valides du cache. Si [failure] est non nul, le
/// rafraîchissement a échoué : un bandeau l'indique au-dessus des données.
final class DataCached<T> extends DataState<T> {
  const DataCached(
    this.data,
    this.updatedAt, {
    this.failure,
    this.isRefreshing = false,
  });

  @override
  final T data;

  @override
  final DateTime updatedAt;

  @override
  final Failure? failure;

  @override
  final bool isRefreshing;
}

/// Erreur, sans données de secours à afficher.
final class DataError<T> extends DataState<T> {
  const DataError(this.failure);

  @override
  final Failure failure;
}
