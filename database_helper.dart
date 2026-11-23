import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('elnaseh_mesh.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY, sender TEXT, content TEXT, ttl INTEGER,
        lat REAL, lng REAL, timestampMs INTEGER, type TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE delivery_log (
        message_id TEXT, endpoint_id TEXT, PRIMARY KEY (message_id, endpoint_id)
      )
    ''');
  }

  Future<void> saveMessage(Map<String, dynamic> msg) async {
    final db = await database;
    await db.insert('messages', msg, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, dynamic>>> getUnsentMessages(String endpointId) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
    return await db.rawQuery('''
      SELECT * FROM messages 
      WHERE id NOT IN (SELECT message_id FROM delivery_log WHERE endpoint_id = ?)
      AND timestampMs > ?
    ''', [endpointId, cutoff]);
  }

  Future<void> markAsSent(String messageId, String endpointId) async {
    final db = await database;
    await db.insert('delivery_log', {'message_id': messageId, 'endpoint_id': endpointId}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
