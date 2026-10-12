import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/constants/app_constants.dart';
import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/network/failure.dart';

/// Relance automatique des erreurs TRANSITOIRES (timeout, 5xx, coupure).
///
///  * au plus `delays.length` relances (2 par défaut), délai croissant ;
///  * jamais pour une erreur non transitoire : identifiants refusés, session,
///    données illisibles, 4xx… ;
///  * jamais si l'appareil se sait hors ligne : le rechargement se fera au
///    retour du réseau ;
///  * jamais après une annulation.
///
/// Pas de relances imbriquées : chaque unité de travail (connexion API,
/// poignée de main EDC, requête de données) est relancée à un seul niveau.
class RetryPolicy {
  const RetryPolicy({
    this.delays = AppConstants.retryDelays,
    this.isOffline,
  });

  final List<Duration> delays;

  /// Indique si l'appareil est hors ligne (aucune relance dans ce cas).
  final bool Function()? isOffline;

  Future<T> run<T>(
    String label,
    Future<T> Function() action, {
    CancelToken? cancelToken,
  }) async {
    for (int attempt = 0;; attempt++) {
      try {
        return await action();
      } on Failure catch (failure) {
        final bool canRetry = failure.isTransient &&
            attempt < delays.length &&
            !(isOffline?.call() ?? false) &&
            !(cancelToken?.isCancelled ?? false);
        if (!canRetry) rethrow;
        final Duration delay = delays[attempt];
        AppLog.retry(
          '$label : ${failure.runtimeType}'
          '${failure.code == null ? '' : ' ${failure.code}'} → '
          'nouvelle tentative ${attempt + 1}/${delays.length} '
          'dans ${delay.inMilliseconds} ms',
        );
        await Future<void>.delayed(delay);
        if (cancelToken?.isCancelled ?? false) throw const CancelledFailure();
      }
    }
  }
}

/// Politique de relance de l'app (délais nuls dans les tests).
final retryPolicyProvider = Provider<RetryPolicy>((ref) {
  return const RetryPolicy();
});
