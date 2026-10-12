import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/network/scform_config.dart';
import 'package:mygalia/core/session/school_client.dart';
import 'package:mygalia/features/grades/data/grades_parser.dart';
import 'package:mygalia/features/grades/domain/grade.dart';

/// Récupération des notes (§4) : page WebForms `MesNotes.aspx`, avec
/// postback pour changer de semestre.
class GradesRemoteDataSource {
  GradesRemoteDataSource(this._school);

  final SchoolClient _school;

  /// Une page qui contient le sélecteur de semestre n'est jamais prise pour
  /// une page de connexion.
  static const String _dataMarker = 'DropDownLstPeriode';

  /// Notes du semestre [periodValue] (vide : semestre affiché par défaut).
  ///
  /// GET puis, seulement si le semestre demandé diffère du semestre affiché,
  /// postback. Si la session expire entre les deux, l'opération ENTIÈRE est
  /// rejouée (le postback a besoin du formulaire de la même session).
  Future<GradesSnapshot> fetch({
    String periodValue = '',
    CancelToken? cancelToken,
  }) {
    return _school.run(
      'notes',
      (SchoolRequester school) async {
        final Uri uri = school.galiaEdcUri(ScFormConfig.mesNotesPath);
        final GradesPage page = GradesParser.parse(
          await school.getPage(uri, dataMarker: _dataMarker),
        );
        if (periodValue.isEmpty || periodValue == page.selectedPeriod) {
          return page.toSnapshot();
        }
        if (!page.periods.any((SchoolPeriod p) => p.value == periodValue)) {
          throw const DataFailure(
            'Ce semestre n\'est plus proposé par l\'espace école.',
          );
        }

        // Postback (§4.2) : rejouer TOUT le formulaire, puis surcharger les
        // trois valeurs qui simulent le changement du sélecteur.
        final String target =
            page.periodFieldName ?? ScFormConfig.periodSelectName;
        final Map<String, String> form = Map<String, String>.of(page.formFields)
          ..['__EVENTTARGET'] = target
          ..['__EVENTARGUMENT'] = ''
          ..[target] = periodValue;
        final GradesPage switched = GradesParser.parse(
          await school.postForm(uri, form, dataMarker: _dataMarker),
        );
        if (switched.selectedPeriod != null &&
            switched.selectedPeriod != periodValue) {
          throw const DataFailure(
            'L\'espace école n\'a pas affiché le semestre demandé.',
          );
        }
        return switched.toSnapshot();
      },
      cancelToken: cancelToken,
    );
  }
}

final gradesRemoteDataSourceProvider = Provider<GradesRemoteDataSource>((ref) {
  return GradesRemoteDataSource(ref.watch(schoolClientProvider));
});
