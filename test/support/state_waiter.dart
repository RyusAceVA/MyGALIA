import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/presentation/data_state.dart';

/// Attend que l'état d'un provider vérifie [predicate].
Future<DataState<T>> waitForState<T>(
  ProviderContainer container,
  ProviderListenable<DataState<T>> provider,
  bool Function(DataState<T> state) predicate, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final DataState<T> current = container.read(provider);
  if (predicate(current)) return current;
  final Completer<DataState<T>> completer = Completer<DataState<T>>();
  final ProviderSubscription<DataState<T>> subscription = container.listen(
    provider,
    (DataState<T>? previous, DataState<T> next) {
      if (!completer.isCompleted && predicate(next)) completer.complete(next);
    },
  );
  try {
    return await completer.future.timeout(timeout);
  } finally {
    subscription.close();
  }
}
