import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/network/scform_config.dart';
import 'package:mygalia/core/session/school_client.dart';
import 'package:mygalia/features/grades/data/grades_parser.dart';
import 'package:mygalia/features/grades/domain/grade.dart';

/// Récupération des notes (§4) : page WebForms `MesNotes.aspx`, avec
/// postback pour changer de classe (cursus) puis de semestre.
class GradesRemoteDataSource {
  GradesRemoteDataSource(this._school);

  final SchoolClient _school;

  /// Notes de la classe [classValue] et du semestre [periodValue] (vides :
  /// ce que l'espace école affiche par défaut).
  ///
  /// GET puis, seulement si nécessaire, un postback pour la classe et un
  /// pour le semestre, chacun rejouant le formulaire de la page précédente.
  /// Si la session expire en route, l'opération ENTIÈRE est rejouée (un
  /// postback a besoin du formulaire de la même session).
  Future<GradesSnapshot> fetch({
    String classValue = '',
    String periodValue = '',
    CancelToken? cancelToken,
  }) {
    return _school.run(
      'notes',
      (SchoolRequester school) async {
        final Uri uri = school.galiaEdcUri(ScFormConfig.mesNotesPath);
        GradesPage page = GradesParser.parse(
          await school.getPage(uri, marker: GradesParser.pageMarker),
        );
        AppLog.session('page des notes : ${page.describe()}');

        if (classValue.isNotEmpty && classValue != page.selectedClass) {
          final FormSelect? select = page.classSelect;
          if (select == null ||
              !page.classes.any((SchoolClass c) => c.value == classValue)) {
            throw const DataFailure(
              'Ce cursus n\'est plus proposé par l\'espace école.',
            );
          }
          page = GradesParser.parse(
            await school.postForm(
              uri,
              page.postbackFor(select, classValue),
              marker: GradesParser.pageMarker,
            ),
          );
          if (page.selectedClass != classValue) {
            throw const DataFailure(
              'L\'espace école n\'a pas affiché le cursus demandé.',
            );
          }
        }

        if (periodValue.isEmpty || periodValue == page.selectedPeriod) {
          return page.toSnapshot();
        }
        if (!page.periods.any((SchoolPeriod p) => p.value == periodValue)) {
          throw const DataFailure(
            'Ce semestre n\'est plus proposé par l\'espace école.',
          );
        }

        // Postback (§4.2) : rejouer TOUT le formulaire, puis surcharger les
        // valeurs qui simulent le changement du sélecteur.
        final FormSelect select = page.periodSelect ??
            const FormSelect(
              name: ScFormConfig.periodSelectName,
              autoPostBack: true,
            );
        final GradesPage switched = GradesParser.parse(
          await school.postForm(
            uri,
            page.postbackFor(select, periodValue),
            marker: GradesParser.pageMarker,
          ),
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
