import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class SavedRecipe {
  const SavedRecipe({
    this.id,
    required this.title,
    required this.contentMarkdown,
    required this.calories,
    required this.savedAt,
  });

  final int? id;
  final String title;
  final String contentMarkdown;
  final String calories;
  final DateTime savedAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'content_markdown': contentMarkdown,
      'calories': calories,
      'saved_at': savedAt.toIso8601String(),
    };
  }

  factory SavedRecipe.fromMap(Map<String, Object?> map) {
    return SavedRecipe(
      id: map['id'] as int?,
      title: map['title'] as String,
      contentMarkdown: map['content_markdown'] as String,
      calories: map['calories'] as String,
      savedAt: DateTime.parse(map['saved_at'] as String),
    );
  }
}

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  static const _databaseName = 'masakin.db';
  static const _databaseVersion = 1;
  static const tableSavedRecipes = 'saved_recipes';

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;

    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, _databaseName);

    return _database = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableSavedRecipes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content_markdown TEXT NOT NULL,
        calories TEXT NOT NULL,
        saved_at TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertSavedRecipe(SavedRecipe recipe) async {
    final db = await database;
    return db.insert(
      tableSavedRecipes,
      recipe.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> deleteSavedRecipe(int id) async {
    final db = await database;
    return db.delete(tableSavedRecipes, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteSavedRecipeByTitle(String title) async {
    final db = await database;
    return db.delete(
      tableSavedRecipes,
      where: 'LOWER(title) = LOWER(?)',
      whereArgs: [title.trim()],
    );
  }

  Future<bool> isRecipeSaved(String title) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) return false;

    final db = await database;
    final rows = await db.query(
      tableSavedRecipes,
      columns: const ['id'],
      where: 'LOWER(title) = LOWER(?)',
      whereArgs: [normalizedTitle],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<SavedRecipe>> fetchSavedRecipes() async {
    final db = await database;
    final rows = await db.query(tableSavedRecipes, orderBy: 'saved_at DESC');
    return rows.map(SavedRecipe.fromMap).toList(growable: false);
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
