import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/presentation/data_loader.dart';
import 'package:mygalia/core/presentation/data_state.dart';
import 'package:mygalia/core/storage/cache_store.dart';
import 'package:mygalia/features/grades/data/grades_repository.dart';
import 'package:mygalia/features/grades/domain/grade.dart';

/// Cursus (classe) demandé : vide = celui affiché par défaut par l'école.
final gradesClassProvider = StateProvider.autoDispose<String>((ref) => '');

/// Semestre demandé : vide = semestre affiché par défaut par l'école.
final gradesPeriodProvider = StateProvider.autoDispose<String>((ref) => '');

/// Derniers cursus et semestres connus : les sélecteurs restent visibles
/// pendant le chargement d'un autre choix.
final knownClassesProvider = StateProvider.autoDispose<List<SchoolClass>>(
  (ref) => const <SchoolClass>[],
);
final knownPeriodsProvider = StateProvider.autoDispose<List<SchoolPeriod>>(
  (ref) => const <SchoolPeriod>[],
);

/// Clé d'un contrôleur de notes : le semestre seul pour le cursus par
/// défaut (« » ou « 31 »), sinon « classe|semestre » (« 17| », « 17|30 »).
String gradesKey({String classValue = '', String period = ''}) =>
    classValue.isEmpty ? period : '$classValue|$period';

/// Un contrôleur par cursus et par semestre (voir [gradesKey]).
final gradesControllerProvider = NotifierProvider.autoDispose
    .family<GradesController, DataState<GradesSnapshot>, String>(
  GradesController.new,
);

class GradesController
    extends AutoDisposeFamilyNotifier<DataState<GradesSnapshot>, String>
    with DataLoader<GradesSnapshot, String> {
  @override
  DataState<GradesSnapshot> build(String key) => startLoading();

  String get _class => arg.contains('|') ? arg.split('|').first : '';
  String get _period => arg.contains('|') ? arg.split('|').last : arg;

  @override
  String get label => 'notes (${_class.isEmpty ? 'cursus par défaut' : 'classe $_class'}, '
      '${_period.isEmpty ? 'semestre courant' : 'semestre $_period'})';

  @override
  CachedValue<GradesSnapshot>? readCache() =>
      ref.read(gradesRepositoryProvider).cached(_period, classValue: _class);

  @override
  Future<CachedValue<GradesSnapshot>> fetch(CancelToken cancelToken) => ref
      .read(gradesRepositoryProvider)
      .fetch(_period, classValue: _class, cancelToken: cancelToken);
}
