import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/debug/app_log.dart';
import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/storage/secure_storage_service.dart';
import 'package:mygalia/features/grades/data/grades_remote_data_source.dart';
import 'package:mygalia/features/grades/domain/grade.dart';
import 'package:mygalia/features/notifications/data/notification_gateway.dart';
import 'package:mygalia/features/notifications/data/notification_store.dart';
import 'package:mygalia/features/notifications/domain/notification_state.dart';
import 'package:mygalia/features/schedule/data/schedule_remote_data_source.dart';
import 'package:mygalia/features/schedule/domain/course.dart';

/// Une vérification en arrière-plan : nouvelles notes, rappel du vendredi.
///
///  * Ne lit ni n'écrit le cache Hive (ouvert par l'app dans un autre
///    isolat) : les pages sont demandées directement, la mémoire est dans le
///    coffre.
///  * Sobre : une requête pour les notes ; cinq pour le planning, une seule
///    fois par semaine. Les relances restent celles de `RetryPolicy`.
///  * N'échoue jamais : une erreur (réseau, serveur, page illisible) est
///    simplement retentée à la vérification suivante.
class NotificationChecker {
  NotificationChecker({
    required NotificationStore store,
    required SecureStorageService vault,
    required GradesRemoteDataSource grades,
    required ScheduleRemoteDataSource schedule,
    required NotificationGateway gateway,
    DateTime Function()? clock,
  })  : _store = store,
        _vault = vault,
        _grades = grades,
        _schedule = schedule,
        _gateway = gateway,
        _clock = clock ?? DateTime.now;

  final NotificationStore _store;
  final SecureStorageService _vault;
  final GradesRemoteDataSource _grades;
  final ScheduleRemoteDataSource _schedule;
  final NotificationGateway _gateway;
  final DateTime Function() _clock;

  Future<void> run() async {
    final NotificationState state = await _store.read();
    if (!state.anyEnabled) return;
    // Déconnecté : rien à vérifier, et surtout aucune tentative de connexion.
    if (await _vault.readCredentials() == null) return;
    if (state.newGrades) await _guard('notes', _checkGrades);
    if (state.fridayReminder) await _guard('rappel du vendredi', _checkFriday);
  }

  Future<void> _checkGrades() async {
    final GradesSnapshot snapshot = await _grades.fetch();
    List<Grade> fresh = const <Grade>[];
    await _store.update((NotificationState current) {
      final GradeCheck check = checkGrades(current, snapshot.grades);
      fresh = check.fresh;
      return check.state;
    });
    if (fresh.isNotEmpty) {
      await _gateway.show(NotificationKind.newGrades, describeNewGrades(fresh));
    }
  }

  Future<void> _checkFriday() async {
    final DateTime? monday = FridayReminder.weekToAnnounce(_clock());
    if (monday == null) return;
    final String key = FridayReminder.weekKey(monday);
    if ((await _store.read()).remindedWeek == key) return;
    final WeekSchedule week = await _schedule.fetchWeek(monday);
    final NotificationText? text = FridayReminder.describe(week);
    if (text != null) await _gateway.show(NotificationKind.fridayReminder, text);
    // Semaine traitée, avec ou sans cours : pas de nouvelle requête d'ici
    // la semaine suivante.
    await _store.update((NotificationState s) => s.copyWith(remindedWeek: key));
  }

  Future<void> _guard(String label, Future<void> Function() check) async {
    try {
      await check();
    } on Failure catch (failure) {
      AppLog.lifecycle('arrière-plan, $label : échec ${failure.runtimeType}');
    } on Object catch (error) {
      AppLog.error('arrière-plan, $label : erreur inattendue (${error.runtimeType})');
    }
  }
}

final notificationCheckerProvider = Provider<NotificationChecker>((ref) {
  return NotificationChecker(
    store: ref.watch(notificationStoreProvider),
    vault: ref.watch(secureStorageServiceProvider),
    grades: ref.watch(gradesRemoteDataSourceProvider),
    schedule: ref.watch(scheduleRemoteDataSourceProvider),
    gateway: ref.watch(notificationGatewayProvider),
  );
});
