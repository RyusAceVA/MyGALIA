import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/constants/app_constants.dart';
import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/lifecycle/refresh_signals.dart';
import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/core/storage/cache_store.dart';

/// Comportement commun des contrôleurs d'écran (planning, notes).
///
///  * [refresh] (Réessayer, pull-to-refresh) déclenche une VRAIE requête
///    réseau : on ne réémet pas un état. Si une requête est déjà en cours,
///    son résultat est partagé (pas de doublon vers le serveur).
///  * Aucun état ne reste bloqué : chaque chargement publie toujours un état
///    final (succès, cache + bandeau, ou erreur), même sur exception
///    inattendue, et libère la place pour le suivant.
///  * Riverpod réutilise l'instance du contrôleur quand il reconstruit le
///    provider : chaque `build` ouvre une nouvelle « époque ». Le résultat
///    d'une requête lancée avant n'est jamais publié après.
///  * À la destruction (écran fermé, semaine quittée, déconnexion), la
///    requête en cours est annulée.
///  * Rechargement automatique au retour du réseau ou au premier plan,
///    seulement si le dernier essai a échoué ou si les données sont
///    anciennes, et jamais en rafale.
mixin DataLoader<T, A> on AutoDisposeFamilyNotifier<DataState<T>, A> {
  int _epoch = 0;
  CancelToken? _cancelToken;
  Future<void>? _inFlight;
  DateTime? _lastAutoRefresh;

  /// Nom lisible pour les journaux de diagnostic.
  String get label;

  /// Dernières données valides connues (cache), ou `null`.
  CachedValue<T>? readCache();

  /// Données fraîches du réseau (mises en cache par le repository).
  Future<CachedValue<T>> fetch(CancelToken cancelToken);

  /// Horloge (surchargée dans les tests).
  DateTime now() => DateTime.now();

  /// À appeler dans `build` : état initial, puis chargement réseau si le
  /// cache est absent ou trop ancien.
  DataState<T> startLoading() {
    final int epoch = ++_epoch;
    final CancelToken token = CancelToken();
    _cancelToken = token;
    _inFlight = null;
    ref.onDispose(() {
      _epoch++;
      _inFlight = null;
      token.cancel('écran fermé');
    });
    final StreamSubscription<RefreshReason> signals = ref
        .read(refreshSignalsProvider)
        .stream
        .listen((RefreshReason reason) => _onSignal(epoch, reason));
    ref.onDispose(signals.cancel);

    final CachedValue<T>? cached = readCache();
    final bool fetchNow = cached == null ||
        now().difference(cached.savedAt) > AppConstants.initialFetchAfter;
    if (fetchNow) {
      // Microtâche : build() doit d'abord exposer l'état initial.
      Future<void>.microtask(() {
        if (epoch == _epoch) _start(epoch, token, 'ouverture');
      });
    } else {
      AppLog.cache('$label : cache récent affiché sans requête');
    }
    if (cached == null) return DataLoading<T>();
    return DataCached<T>(cached.data, cached.savedAt, isRefreshing: fetchNow);
  }

  /// Rafraîchissement explicite : interroge TOUJOURS le réseau. Le Future se
  /// termine quand l'état final est publié (fin du pull-to-refresh).
  Future<void> refresh() {
    final Future<void>? inFlight = _inFlight;
    if (inFlight != null) {
      AppLog.lifecycle('$label : chargement déjà en cours, réutilisé');
      return inFlight;
    }
    final CancelToken? token = _cancelToken;
    if (token == null || token.isCancelled) return Future<void>.value();
    return _start(_epoch, token, 'manuel');
  }

  /// Signal de rechargement automatique : utile seulement si le dernier
  /// essai a échoué ou si les données sont anciennes.
  void _onSignal(int epoch, RefreshReason reason) {
    if (epoch != _epoch || _inFlight != null) return;
    final DataState<T> current = state;
    final DateTime? updatedAt = current.updatedAt;
    final bool failed = current.failure != null;
    final bool stale = updatedAt == null ||
        now().difference(updatedAt) > AppConstants.autoRefreshAfter;
    if (!failed && !stale) return;
    final DateTime at = now();
    final DateTime? last = _lastAutoRefresh;
    if (last != null && at.difference(last) < AppConstants.minAutoRefreshInterval) {
      AppLog.lifecycle('$label : rechargement auto ignoré (anti-rafale)');
      return;
    }
    final CancelToken? token = _cancelToken;
    if (token == null || token.isCancelled) return;
    _lastAutoRefresh = at;
    _start(epoch, token, reason.label);
  }

  Future<void> _start(int epoch, CancelToken token, String reason) {
    late final Future<void> load;
    load = _load(epoch, token, reason).whenComplete(() {
      // Exécuté après l'affectation ci-dessous, même si _load s'est terminé
      // de façon synchrone : la place est toujours libérée.
      if (identical(_inFlight, load)) _inFlight = null;
    });
    _inFlight = load;
    return load;
  }

  /// Ne lève jamais : toute issue publie un état final.
  Future<void> _load(int epoch, CancelToken token, String reason) async {
    AppLog.lifecycle('$label : chargement réseau ($reason)');
    _publish(epoch, _refreshing(state));
    try {
      final CachedValue<T> fresh = await fetch(token);
      _publish(epoch, DataSuccess<T>(fresh.data, fresh.savedAt));
    } on CancelledFailure {
      AppLog.lifecycle('$label : chargement annulé');
    } on Failure catch (failure) {
      AppLog.lifecycle(
        '$label : échec ${failure.runtimeType}'
        '${failure.code == null ? '' : ' ${failure.code}'}',
      );
      _publish(epoch, _failed(state, failure));
    } on Object catch (error) {
      AppLog.error('$label : erreur inattendue (${error.runtimeType})');
      _publish(
        epoch,
        _failed(
          state,
          UnknownFailure('Une erreur inattendue est survenue.', cause: error),
        ),
      );
    }
  }

  void _publish(int epoch, DataState<T> next) {
    if (epoch == _epoch) state = next;
  }

  DataState<T> _refreshing(DataState<T> current) => switch (current) {
        DataSuccess<T>(:final T data, :final DateTime updatedAt) =>
          DataSuccess<T>(data, updatedAt, isRefreshing: true),
        DataCached<T>(:final T data, :final DateTime updatedAt, :final Failure? failure) =>
          DataCached<T>(data, updatedAt, failure: failure, isRefreshing: true),
        DataLoading<T>() || DataError<T>() => DataLoading<T>(),
      };

  DataState<T> _failed(DataState<T> current, Failure failure) => switch (current) {
        DataSuccess<T>(:final T data, :final DateTime updatedAt) ||
        DataCached<T>(:final T data, :final DateTime updatedAt) =>
          DataCached<T>(data, updatedAt, failure: failure),
        DataLoading<T>() || DataError<T>() => DataError<T>(failure),
      };
}
