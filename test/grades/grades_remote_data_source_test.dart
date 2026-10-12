import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/features/grades/data/grades_remote_data_source.dart';
import 'package:mygalia/features/grades/domain/grade.dart';

import '../support/test_env.dart';

void main() {
  late TestEnv env;
  late GradesRemoteDataSource source;

  setUp(() async {
    env = await TestEnv.start();
    await env.storeCredentials();
    source = env.container.read(gradesRemoteDataSourceProvider);
  });

  tearDown(() => env.dispose());

  test('semestre par défaut : un GET, pas de postback', () async {
    final GradesSnapshot snapshot = await source.fetch();

    expect(snapshot.selectedPeriod, '30');
    expect(snapshot.grades, hasLength(2));
    expect(env.server.notesGetCalls, 1);
    expect(env.server.notesPostCalls, 0);
  });

  test('autre semestre : postback avec le formulaire complet', () async {
    final GradesSnapshot snapshot = await source.fetch(periodValue: '31');

    expect(snapshot.selectedPeriod, '31');
    expect(snapshot.grades.single.subject, 'Anglais technique');
    expect(env.server.notesPostCalls, 1);
  });

  test('semestre déjà affiché : aucun postback inutile', () async {
    await source.fetch(periodValue: '30');

    expect(env.server.notesPostCalls, 0);
  });

  test('semestre inconnu : DataFailure claire', () async {
    await expectLater(
      source.fetch(periodValue: '99'),
      throwsA(isA<DataFailure>()),
    );
  });

  test('session expirée entre le GET et le postback : opération rejouée en entier', () async {
    await source.fetch();
    env.server.expireAfterNextNotesGet = true;

    final GradesSnapshot snapshot = await source.fetch(periodValue: '31');

    expect(snapshot.grades.single.subject, 'Anglais technique');
    expect(env.sessions.renewalCount, 2);
    expect(env.server.notesPostCalls, 2, reason: 'postback refusé puis rejoué');
    expect(env.server.notesGetCalls, 3, reason: '1er fetch, GET de l\'opération, GET du rejeu');
  });
}
