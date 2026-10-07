import 'dart:convert';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/corenergy_engage.dart';

class DbHelper {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final pathString = join(docsDir.path, 'pims_mcp_offline.db');
    return await openDatabase(
      pathString,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pending_engagements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            temp_id TEXT UNIQUE,
            data TEXT,
            action_type TEXT,
            timestamp INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE pending_institutions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            temp_id TEXT UNIQUE,
            data TEXT,
            timestamp INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_engagements (
            name TEXT PRIMARY KEY,
            data TEXT,
            timestamp INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_institutions (
            name TEXT PRIMARY KEY,
            data TEXT,
            timestamp INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE pending_institutions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              temp_id TEXT UNIQUE,
              data TEXT,
              timestamp INTEGER
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE cached_engagements (
              name TEXT PRIMARY KEY,
              data TEXT,
              timestamp INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE cached_institutions (
              name TEXT PRIMARY KEY,
              data TEXT,
              timestamp INTEGER
            )
          ''');
        }
      },
    );
  }

  static Future<void> insertPendingEngagement(COREnergyEngage engage, String actionType) async {
    final dataString = jsonEncode(engage.toJson());
    await insertPendingRaw(engage.name, dataString, actionType);
  }

  static Future<void> insertPendingRaw(String tempId, String dataString, String actionType) async {
    final db = await database;
    await db.insert(
      'pending_engagements',
      {
        'temp_id': tempId,
        'data': dataString,
        'action_type': actionType,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getPendingEngagements() async {
    final db = await database;
    return await db.query('pending_engagements', orderBy: 'timestamp ASC');
  }

  static Future<void> deletePendingEngagement(String tempId) async {
    final db = await database;
    await db.delete(
      'pending_engagements',
      where: 'temp_id = ?',
      whereArgs: [tempId],
    );
  }

  static Future<void> insertPendingInstitution(Map<String, dynamic> instJson, String tempId) async {
    final db = await database;
    final dataString = jsonEncode(instJson);
    await db.insert(
      'pending_institutions',
      {
        'temp_id': tempId,
        'data': dataString,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getPendingInstitutions() async {
    final db = await database;
    return await db.query('pending_institutions', orderBy: 'timestamp ASC');
  }

  static Future<void> deletePendingInstitution(String tempId) async {
    final db = await database;
    await db.delete(
      'pending_institutions',
      where: 'temp_id = ?',
      whereArgs: [tempId],
    );
  }

  static Future<void> clearAll() async {
    final db = await database;
    await db.delete('pending_engagements');
    await db.delete('pending_institutions');
  }

  static Future<void> saveCachedEngagement(COREnergyEngage engage) async {
    final db = await database;
    await db.insert(
      'cached_engagements',
      {
        'name': engage.name,
        'data': jsonEncode(engage.toJson()),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> saveCachedEngagementsBatch(List<COREnergyEngage> engages) async {
    final db = await database;
    final batch = db.batch();
    for (var engage in engages) {
      batch.insert(
        'cached_engagements',
        {
          'name': engage.name,
          'data': jsonEncode(engage.toJson()),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<List<COREnergyEngage>> getCachedEngagements() async {
    final db = await database;
    final rows = await db.query('cached_engagements', orderBy: 'timestamp DESC');
    return rows.map((r) => COREnergyEngage.fromJson(jsonDecode(r['data'] as String))).toList();
  }

  static Future<void> saveCachedInstitution(Map<String, dynamic> instJson) async {
    final db = await database;
    final String name = instJson['name'] ?? instJson['institution_name'] ?? DateTime.now().toString();
    await db.insert(
      'cached_institutions',
      {
        'name': name,
        'data': jsonEncode(instJson),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getCachedInstitutions() async {
    final db = await database;
    final rows = await db.query('cached_institutions', orderBy: 'timestamp DESC');
    return rows.map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>).toList();
  }
}
