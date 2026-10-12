import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Journal de diagnostic structuré, **actif uniquement en debug**.
///
/// En release, `kDebugMode` est une constante `false` : chaque appel devient
/// un no-op éliminé à la compilation. Les messages doivent être déjà masqués
/// (voir `Redact`) : jamais de mot de passe, cookie ni jeton.
///
/// Les entrées sont écrites dans logcat (`debugPrint`, tag `flutter`) et
/// conservées en mémoire pour l'écran de diagnostic.
abstract final class AppLog {
  AppLog._();

  static const int _capacity = 400;
  static final ListQueue<LogEntry> _entries = ListQueue<LogEntry>();
  static bool _notifyScheduled = false;

  /// Incrémenté (en différé) à chaque nouvelle entrée : l'écran de
  /// diagnostic s'y abonne pour se rafraîchir.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void session(String message) => _add('session', message);
  static void http(String message) => _add('http', message);
  static void cache(String message) => _add('cache', message);
  static void retry(String message) => _add('retry', message);
  static void lifecycle(String message) => _add('cycle', message);
  static void auth(String message) => _add('auth', message);
  static void error(String message) => _add('erreur', message);

  /// Entrées conservées, de la plus ancienne à la plus récente.
  static List<LogEntry> get entries => List<LogEntry>.unmodifiable(_entries);

  static void clear() {
    if (!kDebugMode) return;
    _entries.clear();
    _scheduleNotify();
  }

  static void _add(String category, String message) {
    if (!kDebugMode) return;
    _entries.addLast(LogEntry(DateTime.now(), category, message));
    while (_entries.length > _capacity) {
      _entries.removeFirst();
    }
    debugPrint('[MyGalia/$category] $message');
    _scheduleNotify();
  }

  /// La notification est différée : un journal écrit pendant la construction
  /// d'un widget ne doit pas déclencher de reconstruction au même moment.
  static void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      revision.value++;
    });
  }
}

/// Une ligne du journal de diagnostic.
@immutable
class LogEntry {
  const LogEntry(this.time, this.category, this.message);

  final DateTime time;
  final String category;
  final String message;
}
