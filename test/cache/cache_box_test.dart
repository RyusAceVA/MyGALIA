import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:mygalia/core/storage/cache_box.dart';
import 'package:mygalia/core/storage/secure_storage_service.dart';

import '../support/hive_test_utils.dart';
import '../support/in_memory_secure_store.dart';

void main() {
  late InMemorySecureKeyValueStore store;
  late SecureStorageService vault;
  late String name;

  setUp(() async {
    // Initialise Hive dans un dossier temporaire.
    await deleteTestBox(await openTestBox());
    store = InMemorySecureKeyValueStore();
    vault = SecureStorageService(store);
    name = 'chiffre_${pid}_${DateTime.now().microsecondsSinceEpoch}';
  });

  tearDown(() => Hive.deleteBoxFromDisk(name));

  test('la clé du cache est stable et survit à la déconnexion', () async {
    final List<int>? first = await vault.cacheKey();
    expect(first, hasLength(32));
    await vault.saveCredentials(const Credentials(email: 'a@b.fr', password: 'x'));

    await vault.clearAll();

    expect(await vault.readCredentials(), isNull);
    expect(await vault.cacheKey(), first);
  });

  test('boîte chiffrée : relue avec la clé, rien en clair sur le disque', () async {
    Box<dynamic> box = await openEncryptedBox(name, vault);
    await box.put('notes', 'ALGORITHMIQUE-SECRETE');
    final String path = box.path!;
    await box.close();

    expect(
      String.fromCharCodes(File(path).readAsBytesSync()),
      isNot(contains('ALGORITHMIQUE-SECRETE')),
    );
    box = await openEncryptedBox(name, vault);
    expect(box.get('notes'), 'ALGORITHMIQUE-SECRETE');
    await box.close();
  });

  test('clé perdue : la boîte repart vide au lieu de bloquer', () async {
    Box<dynamic> box = await openEncryptedBox(name, vault);
    await box.put('notes', 'valeur');
    await box.close();

    store.values.clear();
    box = await openEncryptedBox(name, vault);
    expect(box.get('notes'), isNull);
    await box.close();
  });

  test('coffre indisponible : boîte utilisable mais vidée', () async {
    Box<dynamic> box = await openEncryptedBox(name, vault);
    await box.put('notes', 'valeur');
    await box.close();

    store.failAll = true;
    box = await openEncryptedBox(name, vault);
    expect(box.get('notes'), isNull);
    await box.put('notes', 'autre');
    expect(box.get('notes'), 'autre');
    await box.close();
  });
}
