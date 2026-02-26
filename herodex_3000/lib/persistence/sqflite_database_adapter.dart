import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' show join;
import 'package:hero_common/persistence/database_adapter.dart';

class SqfliteDriver implements DatabaseDriver {
  @override
  Future<DatabaseAdapter> open(String dbName) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
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
