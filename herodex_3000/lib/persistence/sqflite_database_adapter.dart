import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:path/path.dart' show join;
import 'package:hero_common/persistence/database_adapter.dart';

class SqfliteDriver implements DatabaseDriver {
  @override
  Future<DatabaseAdapter> open(String dbName) async {
    if (kIsWeb) {
      // Web: SQLite compiled to WASM, stored in IndexedDB.
      // Use the basic worker variant (not SharedWorker — that returns null
      // in some browser/debug configs; not no-worker — WASM env imports
      // aren't set up correctly on the main thread).
      databaseFactory = databaseFactoryFfiWebBasicWebWorker;
      return SqfliteDatabaseAdapter._(await openDatabase(dbName));
    }
    // On desktop (Windows/Linux/macOS), use FFI; on mobile, use native sqflite.
    final platform = defaultTargetPlatform;
    if (platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS) {
      ffi.sqfliteFfiInit();
      databaseFactory = ffi.databaseFactoryFfi;
    }
    final path = join(await getDatabasesPath(), dbName);
    return SqfliteDatabaseAdapter._(await openDatabase(path, version: 1));
  }
}

class SqfliteDatabaseAdapter implements DatabaseAdapter {
  SqfliteDatabaseAdapter._(this._db);
  final Database _db;

  @override
  Future<void> execute(String sql, [List<Object?> parameters = const []]) async {
    await _db.execute(sql, parameters);
  }

  @override
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?> parameters = const []]) async {
    return await _db.rawQuery(sql, parameters);
  }

  @override
  Future<void> close() async {
    await _db.close();
  }
}
