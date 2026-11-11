import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/features/grades/domain/grade.dart';
import 'package:mygalia/features/notifications/domain/notification_state.dart';
import 'package:mygalia/features/schedule/domain/course.dart';

Grade _grade(String subject, double value, {DateTime? date}) =>
    Grade(value: value, coefficient: 1, subject: subject, date: date);

Course _course(DateTime day, int hour, String subject, {String? room}) => Course(
      start: DateTime(day.year, day.month, day.day, hour, 30),
      end: DateTime(day.year, day.month, day.day, hour + 3),
      subject: subject,
      room: room,
    );

void main() {
  group('nouvelles notes', () {
    test('première liste : point de départ, rien à annoncer', () {
      final GradeCheck check = checkGrades(
        const NotificationState(newGrades: true),
        [_grade('Réseaux', 12), _grade('Anglais', 15)],
      );

      expect(check.fresh, isEmpty);
      expect(check.state.gradesBaseline, isTrue);
      expect(check.state.knownGrades, hasLength(2));
    });

    test('ensuite : seule la note jamais vue est annoncée, une seule fois', () {
      final List<Grade> before = [_grade('Réseaux', 12)];
      final List<Grade> after = [...before, _grade('Anglais', 15)];
      final NotificationState base =
          checkGrades(const NotificationState(newGrades: true), before).state;

      final GradeCheck first = checkGrades(base, after);
      final GradeCheck second = checkGrades(first.state, after);

      expect(first.fresh.single.subject, 'Anglais');
      expect(second.fresh, isEmpty);
    });

    test('une note corrigée (valeur changée) est annoncée', () {
      final NotificationState base = checkGrades(
        const NotificationState(),
        [_grade('Réseaux', 12)],
      ).state;

      expect(checkGrades(base, [_grade('Réseaux', 14)]).fresh, hasLength(1));
    });

    test('empreinte stable, sans contenu lisible', () {
      final Grade grade = _grade('Réseaux', 12, date: DateTime(2026, 11, 2));

      expect(gradeSignature(grade), gradeSignature(_grade('Réseaux', 12, date: DateTime(2026, 11, 2))));
      expect(gradeSignature(grade), isNot(contains('Réseaux')));
      expect(gradeSignature(grade), isNot(gradeSignature(_grade('Réseaux', 12))));
    });

    test('mémoire bornée : les plus anciennes empreintes sont oubliées', () {
      NotificationState state = const NotificationState();
      state = checkGrades(state, [
        for (int i = 0; i < NotificationState.maxKnownGrades + 50; i++)
          _grade('Matière $i', 10),
      ]).state;

      expect(state.knownGrades, hasLength(NotificationState.maxKnownGrades));
      expect(state.knownGrades, contains(gradeSignature(_grade('Matière 449', 10))));
      expect(state.knownGrades, isNot(contains(gradeSignature(_grade('Matière 0', 10)))));
    });

    test('textes : une note, plusieurs notes, mention sans note', () {
      expect(describeNewGrades([_grade('Réseaux', 12.5)]).body, 'Réseaux : 12,5/20');
      expect(
        describeNewGrades([
          const Grade(coefficient: 1, subject: 'Sport', mention: 'ABS'),
        ]).body,
        'Sport : ABS',
      );
      final NotificationText many = describeNewGrades([
        for (int i = 1; i <= 4; i++) _grade('M$i', 10),
      ]);
      expect(many.title, '4 nouvelles notes');
      expect(many.body, 'M1 10/20 · M2 10/20 · M3 10/20…');
    });

    test('état : aller-retour JSON, contenu inattendu toléré', () {
      const NotificationState state = NotificationState(
        newGrades: true,
        gradesBaseline: true,
        knownGrades: {'a', 'b'},
        remindedWeek: '2026-11-16',
      );

      final NotificationState back = NotificationState.fromJson(state.toJson());

      expect(back.newGrades, isTrue);
      expect(back.fridayReminder, isFalse);
      expect(back.knownGrades, {'a', 'b'});
      expect(back.remindedWeek, '2026-11-16');
      expect(NotificationState.fromJson(const {'knownGrades': 3}).anyEnabled, isFalse);
    });
  });

  group('rappel du vendredi', () {
    // Semaine du lundi 9 novembre 2026 ; vendredi 13.
    test('fenêtre : du vendredi midi au dimanche, semaine suivante visée', () {
      expect(FridayReminder.weekToAnnounce(DateTime(2026, 11, 12, 18)), isNull);
      expect(FridayReminder.weekToAnnounce(DateTime(2026, 11, 13, 11, 59)), isNull);
      expect(FridayReminder.weekToAnnounce(DateTime(2026, 11, 13, 12)), DateTime(2026, 11, 16));
      expect(FridayReminder.weekToAnnounce(DateTime(2026, 11, 14, 9)), DateTime(2026, 11, 16));
      expect(FridayReminder.weekToAnnounce(DateTime(2026, 11, 15, 23)), DateTime(2026, 11, 16));
      expect(FridayReminder.weekToAnnounce(DateTime(2026, 11, 16, 7)), isNull);
      expect(FridayReminder.weekKey(DateTime(2026, 3, 2)), '2026-03-02');
    });

    test('semaine avec cours : jours comptés, première séance annoncée', () {
      final DateTime monday = DateTime(2026, 11, 16);
      final WeekSchedule week = WeekSchedule(
        monday: monday,
        courses: [
          _course(DateTime(2026, 11, 18), 13, 'Anglais'),
          _course(DateTime(2026, 11, 17), 8, 'DEVELOPPEMENT WEB', room: 'PITON FOURNAISE'),
          _course(DateTime(2026, 11, 17), 13, 'Réseaux'),
          _course(monday, 8, 'Presence en entreprise'),
        ],
      );

      final NotificationText text = FridayReminder.describe(week)!;

      expect(text.title, 'Cours à l\'école la semaine prochaine');
      expect(text.body, startsWith('2 jours de cours. Reprise '));
      expect(text.body, contains('08:30 : DEVELOPPEMENT WEB (PITON FOURNAISE).'));
    });

    test('semaine en entreprise ou vide : pas de rappel', () {
      final DateTime monday = DateTime(2026, 11, 16);

      expect(
        FridayReminder.describe(WeekSchedule(
          monday: monday,
          courses: [_course(monday, 8, 'Presence en entreprise')],
        )),
        isNull,
      );
      expect(
        FridayReminder.describe(WeekSchedule(monday: monday, courses: const [])),
        isNull,
      );
    });
  });
}
