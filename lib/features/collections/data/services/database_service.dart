import 'dart:async';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/core/utils/storage_path_provider.dart';
import 'package:fav_app/features/collections/data/services/file_storage_service.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();

  static DatabaseService get instance => _instance;

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  final Completer<Database> _dbCompleter = Completer<Database>();
  Future<Database>? _initFuture;

  /// Returns the resolved database file path, creating parent directories if needed.
  static Future<String> resolveDbPath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbDir = Directory(p.join(docsDir.path, 'databases'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    return p.join(dbDir.path, AppConstants.dbName);
  }

  /// 保证并发访问只初始化一次，避免重复 complete 抛出
  /// 「Bad state: Future already completed」。
  Future<Database> get database {
    return _initFuture ??= _initDatabase().then((_) => _dbCompleter.future);
  }

  Future<void> _initDatabase() async {
    final path = await resolveDbPath();

    final db = await openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    _dbCompleter.complete(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2：新增 tags 列，存储 AI 生成的标签
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE collections ADD COLUMN tags TEXT');
    }
    // v2 → v3：评论区模式，多条笔记独立成表；已有 note 迁移为首条笔记
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE collection_notes (
          id TEXT PRIMARY KEY,
          collection_id TEXT,
          content TEXT,
          created_at TEXT
        )
      ''');
      await db.execute('''
        CREATE INDEX idx_collection_notes_collection_id
        ON collection_notes(collection_id)
      ''');
      await db.execute('''
        INSERT INTO collection_notes (id, collection_id, content, created_at)
        SELECT lower(hex(randomblob(16))), id, note, datetime('now')
        FROM collections WHERE note IS NOT NULL AND trim(note) != ''
      ''');
    }
    // v3 → v4：FTS 改为独立表（去掉 content='collections'），
    // 修复外部内容表缺少 content_text 列导致 DELETE/同步报错的问题，
    // 并重建全文索引（正文从文件系统读回）。
    if (oldVersion < 4) {
      await db.execute('DROP TABLE collections_fts');
      await db.execute(
        'CREATE VIRTUAL TABLE collections_fts USING fts5(title, note, content_text)',
      );
      final fileStorage = FileStorageService(StoragePathProvider());
      final rows = await db.query('collections');
      for (final row in rows) {
        final id = row['id'] as String;
        final content = await fileStorage.loadContent(id);
        await db.rawInsert(
          'INSERT INTO collections_fts(rowid, title, note, content_text) '
          'VALUES ((SELECT rowid FROM collections WHERE id=?), ?, ?, ?)',
          [id, row['title'] ?? '', row['note'] ?? '', content],
        );
      }
    }
    // v4 → v5：新增标签注册表（手动创建的标签名，供 AI 保存时优先关联）
    if (oldVersion < 5) {
      await db.execute(
        'CREATE TABLE tags (name TEXT PRIMARY KEY, created_at TEXT)',
      );
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE collections (
        id TEXT PRIMARY KEY,
        title TEXT,
        type TEXT,
        source_platform TEXT,
        source_url TEXT,
        author TEXT,
        published_at TEXT,
        collected_at TEXT,
        category_json TEXT,
        images_json TEXT,
        note TEXT,
        status TEXT,
        review_due_at TEXT,
        tags TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT,
        parent_id TEXT,
        sort_order INTEGER,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_categories_parent_id ON categories(parent_id)
    ''');

    await db.execute('''
      CREATE TABLE tags (
        name TEXT PRIMARY KEY,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE collection_notes (
        id TEXT PRIMARY KEY,
        collection_id TEXT,
        content TEXT,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_collection_notes_collection_id
      ON collection_notes(collection_id)
    ''');

    await db.execute('''
      CREATE VIRTUAL TABLE collections_fts USING fts5(
        title,
        note,
        content_text
      )
    ''');
  }
}
