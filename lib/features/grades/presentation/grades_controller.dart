import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/presentation/data_loader.dart';
import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/core/storage/cache_store.dart';
import 'package:mygalia/features/grades/data/grades_repository.dart';
import 'package:mygalia/features/grades/domain/grade.dart';

/// Semestre demandé : vide = semestre affiché par défaut par l'école.
final gradesPeriodProvider = StateProvider.autoDispose<String>((ref) => '');

/// Derniers semestres connus : le sélecteur reste visible pendant le
/// chargement d'un autre semestre.
final knownPeriodsProvider = StateProvider.autoDispose<List<SchoolPeriod>>(
  (ref) => const <SchoolPeriod>[],
);

/// Un contrôleur par semestre.
final gradesControllerProvider = NotifierProvider.autoDispose
    .family<GradesController, DataState<GradesSnapshot>, String>(
  GradesController.new,
);

class GradesController
    extends AutoDisposeFamilyNotifier<DataState<GradesSnapshot>, String>
    with DataLoader<GradesSnapshot, String> {
  @override
  DataState<GradesSnapshot> build(String period) => startLoading();

  @override
  String get label => 'notes ${arg.isEmpty ? '(semestre courant)' : '(semestre $arg)'}';

  @override
  CachedValue<GradesSnapshot>? readCache() =>
      ref.read(gradesRepositoryProvider).cached(arg);

  @override
  Future<CachedValue<GradesSnapshot>> fetch(CancelToken cancelToken) =>
      ref.read(gradesRepositoryProvider).fetch(arg, cancelToken: cancelToken);
}
