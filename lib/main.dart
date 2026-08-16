import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Use the bundled SQLite (via sqlite3_flutter_libs) which includes FTS5,
  // avoiding the Android system SQLite that often lacks the fts5 module.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  runApp(
    const ProviderScope(
      child: FavApp(),
    ),
  );
}
