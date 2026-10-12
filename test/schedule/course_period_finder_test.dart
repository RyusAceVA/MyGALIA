import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/features/schedule/domain/course.dart';
import 'package:mygalia/features/schedule/domain/course_period_finder.dart';

/// Planning d'alternance fictif, semaine par semaine (lundi → contenu).
class _Plan {
  final Map<DateTime, List<Course>> _byMonday = <DateTime, List<Course>>{};
  int loads = 0;

  static DateTime day(DateTime monday, int offset) =>
      DateTime(monday.year, monday.month, monday.day + offset);

  void school(DateTime monday, [List<int> days = const [0, 1, 2, 3, 4]]) {
    for (final int d in days) {
      final DateTime at = day(monday, d);
      _byMonday.putIfAbsent(monday, () => <Course>[]).add(Course(
            start: at.add(const Duration(hours: 8, minutes: 30)),
            end: at.add(const Duration(hours: 12)),
            subject: 'DEVELOPPEMENT WEB',
          ));
    }
  }

  void company(DateTime monday) {
    for (int d = 0; d < 5; d++) {
      final DateTime at = day(monday, d);
      _byMonday.putIfAbsent(monday, () => <Course>[]).add(Course(
            start: at.add(const Duration(hours: 8, minutes: 30)),
            end: at.add(const Duration(hours: 12)),
            subject: 'Presence en entreprise',
            group: 'ASR11',
          ));
    }
  }

  Future<WeekSchedule> load(DateTime monday) async {
    loads++;
    return WeekSchedule(monday: monday, courses: _byMonday[monday] ?? const <Course>[]);
  }
}

DateTime _w(int week) => DateTime(2026, 10, 5 + 7 * week); // lundis à partir du 5/10

void main() {
  late _Plan plan;
  late CoursePeriodFinder finder;

  setUp(() {
    // W1-W2 entreprise, W3 école, W4 entreprise, W5 école lun-mar puis rien
    // (3 jours vides = vacances), W6 école sauf le mercredi, W7 école,
    // W8 vide (vacances), W9 école.
    plan = _Plan()
      ..company(_w(1))
      ..company(_w(2))
      ..school(_w(3))
      ..company(_w(4))
      ..school(_w(5), [0, 1])
      ..school(_w(6), [0, 1, 3, 4])
      ..school(_w(7))
      ..school(_w(9));
    finder = CoursePeriodFinder(plan.load);
  });

  test('présence en entreprise reconnue (« Presence en entreprise »)', () {
    expect(dayKindOf(plan._byMonday[_w(1)]!.take(1)), DayKind.company);
    expect(dayKindOf(plan._byMonday[_w(3)]!.take(1)), DayKind.school);
    expect(dayKindOf(const <Course>[]), DayKind.empty);
  });

  test('depuis l\'entreprise : premier jour de la prochaine période de cours', () async {
    expect(await finder.nextPeriodStart(_w(1)), _w(3));
  });

  test('depuis une période de cours : la suivante, après l\'entreprise', () async {
    expect(await finder.nextPeriodStart(_Plan.day(_w(3), 2)), _w(5));
  });

  test('un jour libre au milieu ne coupe pas une période', () async {
    // W6 (mercredi libre) et W7 forment une seule période : depuis le lundi
    // de W6, la suivante est W9 (après les vacances de W8), pas jeudi W6.
    expect(await finder.nextPeriodStart(_w(6)), _w(9));
    expect(await finder.nextPeriodStart(_Plan.day(_w(6), 3)), _w(9));
  });

  test('trois jours ouvrés sans rien = vacances : nouvelle période', () async {
    // W5 : cours lun-mar, rien mer-ven → la période suivante commence en W6.
    expect(await finder.nextPeriodStart(_w(5)), _w(6));
  });

  test('période précédente : début de la période d\'avant', () async {
    expect(await finder.previousPeriodStart(_Plan.day(_w(5), 1)), _w(3));
    expect(await finder.previousPeriodStart(_Plan.day(_w(4), 2)), _w(3));
    expect(await finder.previousPeriodStart(_w(9)), _w(6));
  });

  test('prochain jour de cours : ne saute pas la période en cours', () async {
    // Vendredi de W6 (école) → lundi de W7, encore dans la même période.
    expect(await finder.nextSchoolDay(_Plan.day(_w(6), 4)), _w(7));
    // Depuis l'entreprise : premier jour d'école.
    expect(await finder.nextSchoolDay(_w(1)), _w(3));
  });

  test('rien trouvé : null, et pas plus de semaines chargées que la limite', () async {
    final _Plan companyOnly = _Plan();
    for (int w = 0; w < 30; w++) {
      companyOnly.company(_w(w));
    }
    final CoursePeriodFinder limited = CoursePeriodFinder(companyOnly.load, maxWeeks: 4);

    expect(await limited.nextPeriodStart(_w(0)), isNull);
    expect(companyOnly.loads, 4);
  });

  test('chaque semaine n\'est chargée qu\'une fois', () async {
    await finder.nextPeriodStart(_w(1));

    expect(plan.loads, 3, reason: 'W1, W2, W3');
  });
}
