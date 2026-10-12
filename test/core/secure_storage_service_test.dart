import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/storage/secure_storage_service.dart';

import '../support/in_memory_secure_store.dart';

void main() {
  late InMemorySecureKeyValueStore store;
  late SecureStorageService vault;

  setUp(() {
    store = InMemorySecureKeyValueStore();
    vault = SecureStorageService(store);
  });

  test('identifiants : aller-retour et purge', () async {
    await vault.saveCredentials(
      const Credentials(email: 'a@b.fr', password: 'secret'),
    );

    final Credentials? read = await vault.readCredentials();
    expect(read?.email, 'a@b.fr');
    expect(read?.password, 'secret');

    await vault.clearAll();
    expect(await vault.readCredentials(), isNull);
  });

  test('le mot de passe n\'apparaît jamais dans toString()', () {
    const Credentials credentials = Credentials(email: 'a@b.fr', password: 'secret');
    const ApiToken token = ApiToken('eyJhbGciOi');

    expect(credentials.toString(), isNot(contains('secret')));
    expect(credentials.toString(), isNot(contains('a@b.fr')));
    expect(token.toString(), isNot(contains('eyJhbGciOi')));
  });

  test('une entrée corrompue est traitée comme absente puis supprimée', () async {
    store.values['mygalia.credentials'] = '{pas du json';

    expect(await vault.readCredentials(), isNull);
    expect(store.values.containsKey('mygalia.credentials'), isFalse);
  });

  test('un coffre en échec ne bloque jamais la lecture', () async {
    store.failAll = true;

    expect(await vault.readCredentials(), isNull);
    expect(await vault.readApiToken(), isNull);
  });

  test("une écriture impossible devient une CacheFailure claire", () async {
    store.failAll = true;

    expect(
      () => vault.saveCredentials(const Credentials(email: 'a@b.fr', password: 'x')),
      throwsA(isA<CacheFailure>()),
    );
  });

  test('jeton API : utilisable seulement avant son expiration', () {
    final DateTime now = DateTime.utc(2026, 10, 12, 12);

    expect(ApiToken('t', expiresAt: now.add(const Duration(hours: 1))).isUsable(now), isTrue);
    expect(ApiToken('t', expiresAt: now.add(const Duration(minutes: 1))).isUsable(now), isFalse);
    expect(const ApiToken('t').isUsable(now), isTrue);
  });
}
