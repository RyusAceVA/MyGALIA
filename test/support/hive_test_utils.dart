import 'dart:io';

import 'package:hive/hive.dart';

bool _initialized = false;
int _boxCounter = 0;

/// Ouvre une boîte Hive neuve dans un dossier temporaire (une par test).
Future<Box<dynamic>> openTestBox() async {
  if (!_initialized) {
    Hive.init(Directory.systemTemp.createTempSync('mygalia_hive_').path);
    _initialized = true;
  }
  return Hive.openBox<dynamic>('cache_test_${pid}_${_boxCounter++}');
}

/// Ferme et supprime la boîte.
Future<void> deleteTestBox(Box<dynamic> box) => box.deleteFromDisk();
