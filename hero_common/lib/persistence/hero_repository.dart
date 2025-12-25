import 'package:hero_common/jobs/job_queue.dart';
import 'package:hero_common/models/hero_model.dart';
import 'package:hero_common/persistence/database_adapter.dart';
import 'package:hero_common/persistence/hero_repositing.dart';

class HeroRepository implements HeroRepositing {
  HeroRepository._(this._db, this._cache);

  static Future<HeroRepository> create(String path, DatabaseDriver driver) async {
    var db = await driver.open(path);
    await createTableIfNotExists(db);
    var snapshot = await readSnapshot(db);
    return HeroRepository._(db, snapshot);
  }

  static Future<void> createTableIfNotExists(DatabaseAdapter db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS heroes (
${HeroModel.generateSqliteColumnDeclarations('    ')}
)''');
  }

  static Future<Map<String, HeroModel>> readSnapshot(DatabaseAdapter db) async {
    var snapshot = <String, HeroModel>{};
    for (var row in await db.select('SELECT * FROM heroes')) {
      var hero = HeroModel.fromRow(row);
      snapshot[hero.id] = hero;
    }
    return snapshot;
  }

  @override
  void persist(HeroModel hero) {
    _cache[hero.id] = hero;
    // Persist a copy to avoid race conditions (technically not needed for inserts but I want to keep the code nice and clean)
    _jobQueue.enqueue(() => dbPersist(HeroModel.from(hero)));
  }

  Future<void> dbPersist(HeroModel hero) async {
    var parameters = hero.sqliteProps().toList();
    await _db.execute('''INSERT INTO heroes (
${HeroModel.generateSqliteColumnNameList('      ')}
) VALUES (${HeroModel.generateSQLiteInsertColumnPlaceholders()})
ON CONFLICT (id) DO
UPDATE
SET ${HeroModel.generateSqliteUpdateClause('    ')}
      ''', parameters);
  }

  @override
  void delete(HeroModel hero) {
    _cache.remove(hero.id);
    _jobQueue.enqueue(() => dbDelete(hero));
  }

  Future<void> dbDelete(HeroModel hero) async {
    await _db.execute('DELETE FROM heroes WHERE id = ?', [hero.id]);
  }

  @override
  void clear() {
    _cache.clear();
    _jobQueue.enqueue(() => dbClean());
  }

  Future<void> dbClean() async {
    await _db.execute('DELETE FROM heroes');
  }

  // TODO: can I make a proper dispose pattern here?
  @override
  Future<Null> dispose() async {
    await _jobQueue.close();
    await _jobQueue.join();
    await _db.close();
    _cache.clear();
  }

  final JobQueue _jobQueue = JobQueue();
  final Map<String, HeroModel> _cache;

  final DatabaseAdapter _db;

  @override
  List<HeroModel> get heroes {
    var snapshot = _cache.values.toList();
    return snapshot;
  }

  @override
  Map<String, HeroModel> get heroesById => Map.unmodifiable(_cache);
}
