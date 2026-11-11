import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/features/schedule/domain/course.dart';
import 'package:mygalia/features/schedule/domain/ics_export.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 10, 10, 9);
  final Course web = Course(
    start: DateTime(2026, 10, 12, 8, 30),
    end: DateTime(2026, 10, 12, 12),
    subject: 'DEVELOPPEMENT WEB',
    group: 'TSRS1',
    teachers: 'DUPONT Jean, MARTIN Zoé',
    room: 'PITON; FOURNAISE',
  );
  final Course company = Course(
    start: DateTime(2026, 10, 13, 8),
    end: DateTime(2026, 10, 13, 17),
    subject: 'Presence en entreprise',
  );

  test('un événement par vrai cours, présence en entreprise exclue', () {
    final String ics = IcsExport.calendar([company, web], now: now);

    expect(ics, startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
    expect('BEGIN:VEVENT'.allMatches(ics), hasLength(1));
    expect(ics, contains('SUMMARY:DEVELOPPEMENT WEB\r\n'));
    expect(ics, isNot(contains('entreprise')));
  });

  test('heures en UTC, lieu et description échappés', () {
    final String ics = IcsExport.calendar([web], now: now);
    String stamp(DateTime local) {
      final DateTime t = local.toUtc();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${t.year}${two(t.month)}${two(t.day)}T${two(t.hour)}${two(t.minute)}00Z';
    }

    expect(ics, contains('DTSTART:${stamp(web.start)}\r\n'));
    expect(ics, contains('DTEND:${stamp(web.end)}\r\n'));
    expect(ics, contains('DTSTAMP:20261010T090000Z\r\n'));
    expect(ics, contains(r'LOCATION:PITON\; FOURNAISE'));
    expect(ics, contains(r'DESCRIPTION:DUPONT Jean\, MARTIN Zoé\nTSRS1'));
  });

  test('identifiant stable d\'un export à l\'autre, distinct par séance', () {
    String uid(Course c, DateTime at) => RegExp(r'UID:(.+)\r\n')
        .firstMatch(IcsExport.calendar([c], now: at))!
        .group(1)!;
    final Course afternoon = Course(
      start: DateTime(2026, 10, 12, 13),
      end: DateTime(2026, 10, 12, 16),
      subject: web.subject,
    );

    expect(uid(web, now), uid(web, now.add(const Duration(days: 3))));
    expect(uid(web, now), isNot(uid(afternoon, now)));
  });

  test('lignes pliées à 75 octets, sans couper un caractère accentué', () {
    final Course long = Course(
      start: DateTime(2026, 10, 12, 8),
      end: DateTime(2026, 10, 12, 9),
      subject: 'Sécurité des systèmes et réseaux étendus — ' * 4,
    );

    final String ics = IcsExport.calendar([long], now: now);

    for (final String line in ics.split('\r\n')) {
      expect(utf8.encode(line).length, lessThanOrEqualTo(75), reason: line);
    }
    // Dépliée, la matière est intacte.
    expect(ics.replaceAll('\r\n ', ''), contains('SUMMARY:${long.subject.trimRight()}'));
  });

  test('nom de fichier et semaine sans cours', () {
    expect(IcsExport.fileName(DateTime(2026, 3, 2)), 'planning-2026-03-02.ics');
    expect(IcsExport.exportable([company]), isEmpty);
  });
}
