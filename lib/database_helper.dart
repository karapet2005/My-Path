import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:latlong2/latlong.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('mypath.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 4, 
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        latitude REAL,
        longitude REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE saved_routes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        distanceKm REAL,
        points TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE stats (
        key TEXT PRIMARY KEY,
        value REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE explored_tiles (
        tile_id TEXT PRIMARY KEY
      )
    ''');
    
    await db.insert('stats', {'key': 'total_km', 'value': 0.0});
    await db.insert('stats', {'key': 'current_streak', 'value': 0.0});
    await db.insert('stats', {'key': 'last_active_date', 'value': 0.0});
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('CREATE TABLE saved_routes (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, distanceKm REAL, points TEXT)');
    }
    if (oldVersion < 3) {
      await db.execute('CREATE TABLE stats (key TEXT PRIMARY KEY, value REAL)');
      await db.insert('stats', {'key': 'total_km', 'value': 0.0});
    }
    if (oldVersion < 4) {
      await db.execute('CREATE TABLE explored_tiles (tile_id TEXT PRIMARY KEY)');
    }
  }

  // --- LOCATIONS (Fog of War) ---
  Future<int> insertLocation(LatLng point) async {
    final db = await instance.database;
    return await db.insert('locations', {'latitude': point.latitude, 'longitude': point.longitude});
  }

  Future<List<LatLng>> getAllLocations() async {
    final db = await instance.database;
    final result = await db.query('locations');
    return result.map((json) => LatLng(json['latitude'] as double, json['longitude'] as double)).toList();
  }

  // --- SAVED ROUTES (Planung) ---
  Future<int> saveRoute(String name, List<LatLng> points, double distanceKm) async {
    final db = await instance.database;
    final pointsString = points.map((p) => "${p.latitude},${p.longitude}").join(';');
    return await db.insert('saved_routes', {'name': name, 'distanceKm': distanceKm, 'points': pointsString});
  }

  Future<List<Map<String, dynamic>>> getAllSavedRoutes() async {
    final db = await instance.database;
    return await db.query('saved_routes');
  }

  // --- STATS (Gesamt-Kilometer) ---
  Future<double> getTotalKm() async {
    final db = await instance.database;
    final result = await db.query('stats', where: 'key = ?', whereArgs: ['total_km']);
    return result.isNotEmpty ? result.first['value'] as double : 0.0;
  }

  Future<void> addTotalKm(double additionalKm) async {
    final db = await instance.database;
    final updated = await getTotalKm() + additionalKm;
    await db.insert('stats', {'key': 'total_km', 'value': updated}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // --- GRID SYSTEM (Kacheln & Aufdecken) ---
  Future<bool> exploreTile(double lat, double lon) async {
    String tileId = "${lat.toStringAsFixed(3)}_${lon.toStringAsFixed(3)}";
    final db = await database;
    final result = await db.query('explored_tiles', where: 'tile_id = ?', whereArgs: [tileId]);
    if (result.isEmpty) {
      await db.insert('explored_tiles', {'tile_id': tileId}, conflictAlgorithm: ConflictAlgorithm.ignore);
      return true; 
    }
    return false;
  }

  Future<int> getExploredTilesCount() async {
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM explored_tiles'));
    return count ?? 0;
  }

  // --- NEU: STREAK SYSTEM (Tägliche Motivation) ---
  Future<int> getStreak() async {
    final db = await instance.database;
    final result = await db.query('stats', where: 'key = ?', whereArgs: ['current_streak']);
    return result.isNotEmpty ? (result.first['value'] as double).toInt() : 0;
  }

  Future<void> updateStreak() async {
    final db = await instance.database;
    final now = DateTime.now();
    final todayAsInt = now.year * 10000 + now.month * 100 + now.day; // z.B. 20260823

    final dateResult = await db.query('stats', where: 'key = ?', whereArgs: ['last_active_date']);
    double lastDate = dateResult.isNotEmpty ? dateResult.first['value'] as double : 0.0;

    int currentStreak = await getStreak();

    if (lastDate == todayAsInt.toDouble()) {
      return; // Heute schon getrackt, Streak bleibt erhalten
    }

    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayAsInt = yesterday.year * 10000 + yesterday.month * 100 + yesterday.day;

    if (lastDate == yesterdayAsInt.toDouble()) {
      currentStreak += 1; // Gestern aktiv -> Streak + 1
    } else {
      currentStreak = 1; // Länger inaktiv -> Streak reset auf 1
    }

    await db.insert('stats', {'key': 'current_streak', 'value': currentStreak.toDouble()}, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('stats', {'key': 'last_active_date', 'value': todayAsInt.toDouble()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}