import 'package:sqlite3/sqlite3.dart' as s3;
import 'package:hero_common/persistence/database_adapter.dart';

class Sqlite3Driver implements DatabaseDriver {
  @override
  Future<DatabaseAdapter> open(String path) async {
    return Sqlite3DatabaseAdapter._(s3.sqlite3.open(path));
  }
}

class Sqlite3DatabaseAdapter implements DatabaseAdapter {
  Sqlite3DatabaseAdapter._(this._db);
  final s3.Database _db;

  @override
  Future<void> execute(String sql, [List<Object?> parameters = const []]) async {
    _db.execute(sql, parameters);
  }

  @override
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?> parameters = const []]) async {
    return _db.select(sql, parameters).toList();
  }

  @override
  Future<void> close() async {
    _db.dispose();
  }
}
