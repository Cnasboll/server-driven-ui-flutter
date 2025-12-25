/// Stateless factory that knows how to open a database connection.
abstract class DatabaseDriver {
  Future<DatabaseAdapter> open(String path);
}

/// Stateful wrapper around an opened database connection.
abstract class DatabaseAdapter {
  Future<void> execute(String sql, [List<Object?> parameters = const []]);
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?> parameters = const []]);
  Future<void> close();
}
