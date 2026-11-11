import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/storage/cache_store.dart';
import 'package:mygalia/features/grades/data/grades_parser.dart';
import 'package:mygalia/features/grades/data/grades_remote_data_source.dart';
import 'package:mygalia/features/grades/data/grades_repository.dart';
import 'package:mygalia/features/grades/domain/grade.dart';

import '../support/fake_scform_server.dart';
import '../support/hive_test_utils.dart';
import '../support/test_env.dart';

const List<SchoolClass> _classes = [
  SchoolClass(value: '23', label: 'BSRC1'),
  SchoolClass(value: '17', label: 'TSRS1'),
];

void main() {
  group('page des notes', () {
    test('un seul cursus : une classe, sélecteur sans rechargement auto', () {
      final GradesPage page =
          GradesParser.parse(FakeScFormServer.notesPageHtml(period: '30'));

      expect(page.classes, const [SchoolClass(value: '17', label: 'TSRS1')]);
      expect(page.selectedClass, '17');
      expect(page.classSelect!.autoPostBack, isFalse);
      expect(page.periodSelect!.autoPostBack, isTrue);
      expect(page.submitButton!.key, r'ctl00$MainContent$BtnValider');
    });

    test('deux cursus : classes, classe affichée, semestres de cette classe', () {
      final GradesPage page = GradesParser.parse(
        FakeScFormServer.notesPageHtml(period: '40', classValue: '23', twoClasses: true),
      );

      expect(page.classes, _classes);
      expect(page.selectedClass, '23');
      expect(page.classSelect!.autoPostBack, isTrue);
      expect(page.periods.single.value, '40');
      expect(page.toSnapshot().classes, _classes);
    });

    test('sélecteur à rechargement auto : événement, jamais le bouton', () {
      final GradesPage page = GradesParser.parse(
        FakeScFormServer.notesPageHtml(period: '40', classValue: '23', twoClasses: true),
      );

      final Map<String, String> form = page.postbackFor(page.classSelect!, '17');

      expect(form['__EVENTTARGET'], r'ctl00$MainContent$DropDownLstClasse');
      expect(form[r'ctl00$MainContent$DropDownLstClasse'], '17');
      expect(form.containsKey(r'ctl00$MainContent$BtnValider'), isFalse);
      expect(form['__VIEWSTATE'], FakeScFormServer.viewStateOf('23'));
    });

    test('sélecteur sans rechargement auto : clic sur « Valider »', () {
      final GradesPage page = GradesParser.parse(
        FakeScFormServer.notesPageHtml(
          period: '40',
          classValue: '23',
          twoClasses: true,
          classAutoPostBack: false,
        ),
      );

      final Map<String, String> form = page.postbackFor(page.classSelect!, '17');

      expect(form['__EVENTTARGET'], isEmpty);
      expect(form[r'ctl00$MainContent$BtnValider'], 'Valider');
    });
  });

  group('récupération', () {
    late TestEnv env;
    late GradesRemoteDataSource source;

    setUp(() async {
      env = await TestEnv.start();
      await env.storeCredentials();
      env.server.twoClasses = true;
      source = env.container.read(gradesRemoteDataSourceProvider);
    });

    tearDown(() => env.dispose());

    test('par défaut : le nouveau cursus, sans postback', () async {
      final GradesSnapshot snapshot = await source.fetch();

      expect(snapshot.selectedClass, '23');
      expect(snapshot.classes, _classes);
      expect(snapshot.grades.single.subject, 'Cloud');
      expect(env.server.notesPostCalls, 0);
    });

    for (final bool auto in <bool>[true, false]) {
      test('ancien cursus (${auto ? 'rechargement auto' : 'bouton Valider'})', () async {
        env.server.classAutoPostBack = auto;

        final GradesSnapshot snapshot = await source.fetch(classValue: '17');

        expect(snapshot.selectedClass, '17');
        expect(snapshot.selectedPeriod, '30');
        expect(snapshot.periods.map((SchoolPeriod p) => p.value), ['31', '30']);
        expect(snapshot.grades, hasLength(2));
        expect(env.server.notesPostCalls, 1);
      });

      test('ancien cursus, autre semestre (${auto ? 'auto' : 'bouton'}) : deux postbacks enchaînés',
          () async {
        env.server.classAutoPostBack = auto;

        final GradesSnapshot snapshot =
            await source.fetch(classValue: '17', periodValue: '31');

        expect(snapshot.selectedClass, '17');
        expect(snapshot.selectedPeriod, '31');
        expect(snapshot.grades.single.subject, 'Anglais technique');
        expect(env.server.notesPostCalls, 2);
      });
    }

    test('cursus déjà affiché : aucun postback inutile', () async {
      await source.fetch(classValue: '23');

      expect(env.server.notesPostCalls, 0);
    });

    test('cursus inconnu : DataFailure claire', () async {
      await expectLater(
        source.fetch(classValue: '99'),
        throwsA(isA<DataFailure>()),
      );
    });

    test('semestre de l\'ancien cursus demandé dans le nouveau : refusé', () async {
      await expectLater(
        source.fetch(periodValue: '31'),
        throwsA(isA<DataFailure>()),
      );
    });

    test('session expirée avant les postbacks : opération rejouée en entier', () async {
      await source.fetch();
      env.server.expireAfterNextNotesGet = true;

      final GradesSnapshot snapshot =
          await source.fetch(classValue: '17', periodValue: '31');

      expect(snapshot.grades.single.subject, 'Anglais technique');
      expect(env.sessions.renewalCount, 2);
    });
  });

  group('cache', () {
    late TestEnv env;
    late Box<dynamic> box;

    setUp(() async {
      box = await openTestBox();
      env = await TestEnv.start(
        overrides: [cacheStoreProvider.overrideWithValue(CacheStore(box))],
      );
      await env.storeCredentials();
      env.server.twoClasses = true;
    });

    tearDown(() async {
      await env.dispose();
      await deleteTestBox(box);
    });

    test('une entrée par cursus : les notes ne se mélangent pas', () async {
      final GradesRepository grades = env.container.read(gradesRepositoryProvider);

      await grades.fetch('');
      await grades.fetch('', classValue: '17');
      await grades.fetch('31', classValue: '17');

      expect(grades.cached('')!.data.grades.single.subject, 'Cloud');
      expect(grades.cached('', classValue: '17')!.data.grades, hasLength(2));
      expect(
        grades.cached('31', classValue: '17')!.data.grades.single.subject,
        'Anglais technique',
      );
      expect(grades.cached('31'), isNull);
    });
  });
}
