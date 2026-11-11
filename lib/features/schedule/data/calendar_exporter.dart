import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:mygalia/features/schedule/domain/course.dart';
import 'package:mygalia/features/schedule/domain/ics_export.dart';

/// Issue d'un export vers l'agenda.
enum CalendarExportResult {
  /// Fichier remis au système (choix de l'agenda par l'utilisateur).
  shared,

  /// Aucun vrai cours dans la semaine : rien à exporter.
  nothingToExport,

  /// Écriture ou partage impossible.
  failed,
}

/// Exporte une semaine vers l'agenda du téléphone : un fichier `.ics`
/// temporaire, remis à la feuille de partage du système. L'app ne demande
/// aucune permission d'agenda et n'écrit jamais dedans elle-même.
typedef CalendarExporter = Future<CalendarExportResult> Function(WeekSchedule week);

Future<CalendarExportResult> _exportWeek(WeekSchedule week) async {
  if (IcsExport.exportable(week.courses).isEmpty) {
    return CalendarExportResult.nothingToExport;
  }
  try {
    final Directory directory = await getTemporaryDirectory();
    final File file = File('${directory.path}/${IcsExport.fileName(week.monday)}');
    await file.writeAsString(
      IcsExport.calendar(week.courses, now: DateTime.now()),
      flush: true,
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/calendar')],
        subject: 'Planning de la semaine',
      ),
    );
    return CalendarExportResult.shared;
  } on Object {
    return CalendarExportResult.failed;
  }
}

/// Surchargé dans les tests (aucun canal de plateforme).
final calendarExporterProvider = Provider<CalendarExporter>((ref) => _exportWeek);
