import 'package:flutter/material.dart';

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/core/utils/date_format_fr.dart';

/// Affiche un [DataState] :
///  * chargement : indicateur central ;
///  * erreur : explication claire et bouton « Réessayer » ;
///  * données (fraîches ou en cache) : date « Mis à jour … » et, si le
///    rafraîchissement a échoué, un bandeau d'alerte avec « Réessayer ».
///
/// Le pull-to-refresh est disponible dans tous les états (y compris
/// erreur et liste vide) et appelle [onRefresh], qui interroge le réseau.
class DataStateView<T> extends StatelessWidget {
  const DataStateView({
    super.key,
    required this.state,
    required this.onRefresh,
    required this.builder,
  });

  final DataState<T> state;
  final Future<void> Function() onRefresh;
  final List<Widget> Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = switch (state) {
      DataLoading<T>() => const [
          SizedBox(height: 160),
          Center(child: CircularProgressIndicator()),
        ],
      DataError<T>(:final Failure failure) => [
          ErrorPanel(failure: failure, onRetry: onRefresh),
        ],
      DataSuccess<T>(:final T data, :final DateTime updatedAt) => [
          FreshnessLine(updatedAt: updatedAt),
          ...builder(context, data),
        ],
      DataCached<T>(
        :final T data,
        :final DateTime updatedAt,
        :final Failure? failure,
        :final bool isRefreshing,
      ) =>
        [
          if (failure != null)
            StaleDataBanner(
              failure: failure,
              updatedAt: updatedAt,
              onRetry: isRefreshing ? null : onRefresh,
            )
          else
            FreshnessLine(updatedAt: updatedAt, fromCache: true),
          ...builder(context, data),
        ],
    };
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // La marge basse inclut la barre de navigation flottante.
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: children,
      ),
    );
  }
}

/// Fine barre de progression pendant un rafraîchissement en arrière-plan.
class RefreshProgress extends StatelessWidget {
  const RefreshProgress({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 2,
        child: visible ? const LinearProgressIndicator(minHeight: 2) : null,
      );
}

/// Icône et titre décrivant une erreur typée.
(IconData, String) describeFailure(Failure failure) => switch (failure) {
      NetworkFailure(issue: NetworkIssue.offline) =>
        (Icons.wifi_off_rounded, 'Pas de connexion'),
      NetworkFailure(issue: NetworkIssue.timeout) =>
        (Icons.hourglass_empty_rounded, 'Serveur trop lent'),
      NetworkFailure() => (Icons.sync_problem_rounded, 'Connexion interrompue'),
      ServerFailure() => (Icons.cloud_off_rounded, 'Serveur indisponible'),
      SessionFailure() =>
        (Icons.lock_outline_rounded, 'Session impossible à rétablir'),
      InvalidCredentialsFailure() || SignedOutFailure() =>
        (Icons.person_off_outlined, 'Reconnexion nécessaire'),
      DataFailure() => (Icons.broken_image_outlined, 'Données illisibles'),
      CacheFailure() => (Icons.storage_rounded, 'Stockage indisponible'),
      CancelledFailure() || UnknownFailure() =>
        (Icons.error_outline_rounded, 'Erreur inattendue'),
    };

/// Erreur sans données de secours : explication et bouton « Réessayer ».
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.failure, required this.onRetry});

  final Failure failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (IconData icon, String title) = describeFailure(failure);
    return Padding(
      padding: const EdgeInsets.only(top: 96),
      child: Column(
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            failure.message,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}

/// Date des données affichées (« Mis à jour aujourd'hui à 19:30 »).
class FreshnessLine extends StatelessWidget {
  const FreshnessLine({super.key, required this.updatedAt, this.fromCache = false});

  final DateTime updatedAt;
  final bool fromCache;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            fromCache ? Icons.history_rounded : Icons.check_circle_outline_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              DateFormatFr.updatedAt(updatedAt, DateTime.now()),
              style: theme.textTheme.labelMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bandeau : le rafraîchissement a échoué, les données affichées sont les
/// dernières valides connues.
class StaleDataBanner extends StatelessWidget {
  const StaleDataBanner({
    super.key,
    required this.failure,
    required this.updatedAt,
    required this.onRetry,
  });

  final Failure failure;
  final DateTime updatedAt;

  /// `null` pendant qu'un nouvel essai est en cours.
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color onContainer = theme.colorScheme.onErrorContainer;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: onContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rafraîchissement impossible',
                      style: theme.textTheme.titleSmall?.copyWith(color: onContainer),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      failure.message,
                      style: theme.textTheme.bodySmall?.copyWith(color: onContainer),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Données affichées : '
                      '${DateFormatFr.updatedAt(updatedAt, DateTime.now()).replaceFirst('Mis à jour ', '')}.',
                      style: theme.textTheme.labelSmall?.copyWith(color: onContainer),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onRetry,
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
