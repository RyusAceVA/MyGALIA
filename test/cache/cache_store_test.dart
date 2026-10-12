import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:mygalia/core/storage/cache_store.dart';
import 'package:mygalia/features/schedule/domain/course.dart';

import '../support/hive_test_utils.dart';

void main() {
  late Box<dynamic> box;
  late CacheStore cache;
  final DateTime savedAt = DateTime(2026, 10, 12, 19, 30);
  final WeekSchedule week = WeekSchedule(
    monday: DateTime(2026, 10, 12),
    courses: [
      Course(
        start: DateTime(2026, 10, 12, 8, 30),
        end: DateTime(2026, 10, 12, 12),
        subject: 'DEVELOPPEMENT WEB',
        group: 'TSRS1',
      ),
    ],
  );

  setUp(() async {
    box = await openTestBox();
    cache = CacheStore(box);
  });

  tearDown(() => deleteTestBox(box));

  test('aller-retour d\'une valeur valide, avec sa date', () async {
    await cache.write('planning:test', week.toJson(), savedAt);

    final CachedValue<WeekSchedule>? read =
        cache.read('planning:test', WeekSchedule.fromJson);

    expect(read?.savedAt, savedAt);
    expect(read?.data.courses.single.subject, 'DEVELOPPEMENT WEB');
  });

  for (final (String label, Object raw) in [
    ('JSON corrompu', '{"v":1,"savedAt":"2026-'),
    ('ancienne version de format', '{"v":0,"savedAt":"2026-10-12T19:30:00.000","data":{}}'),
    ('structure inattendue', '{"v":1,"savedAt":"2026-10-12T19:30:00.000","data":{"monday":42}}'),
    ('valeur non textuelle', 12345),
  ]) {
    test('entrée illisible ($label) : traitée comme absente et supprimée', () async {
      await box.put('planning:test', raw);

      expect(cache.read('planning:test', WeekSchedule.fromJson), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(box.containsKey('planning:test'), isFalse);
    });
  }

  test('clear vide tout', () async {
    await cache.write('a', week.toJson(), savedAt);
    await cache.clear();

    expect(box.isEmpty, isTrue);
  });
}
