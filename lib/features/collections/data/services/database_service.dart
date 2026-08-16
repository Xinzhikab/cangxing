import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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

    final result = await selfCheckAndRepair(db);
    final ftsRowsInserted = result.ftsRowsInserted;
    final orphanDbRowsDeleted = result.orphanDbRowsDeleted;
    final errors = result.errors;
    debugPrint('[DB SelfCheck] fts补写: $ftsRowsInserted, 孤儿DB行删除: $orphanDbRowsDeleted, 错误: ${errors.length}');
    if (errors.isNotEmpty) {
      for (final e in errors) {
        debugPrint('[DB SelfCheck] error: $e');
      }
    }

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
    // [DEPRECATED] tags 注册表 2026-08-16 起废弃，保留迁移仅为兼容旧版本升级。
    if (oldVersion < 5) {
      await db.execute(
        'CREATE TABLE tags (name TEXT PRIMARY KEY, created_at TEXT)',
      );
    }
    // v5 → v6：回收站功能，collections 表新增 deleted_at 列。
    // NULL 表示正常收藏，非 NULL 为软删除时间戳（毫秒）。
    if (oldVersion < 6) {
      await db.execute(
        'ALTER TABLE collections ADD COLUMN deleted_at INTEGER DEFAULT NULL',
      );
    }
    // v6 → v7：置顶功能，collections 表新增 pinned_at 列。
    // NULL 表示未置顶，非 NULL 为置顶时间戳（毫秒），越大表示越近置顶。
    if (oldVersion < 7) {
      await db.execute(
        'ALTER TABLE collections ADD COLUMN pinned_at INTEGER DEFAULT NULL',
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
        tags TEXT,
        deleted_at INTEGER DEFAULT NULL,
        pinned_at INTEGER DEFAULT NULL
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

    /*
     * [DEPRECATED] `tags` 注册表（2026-08-16 起废弃，只读保留兼容性）
     * 不再写入/维护，tags 权威来源为 collections.tags_json 列。
     * 保留表结构仅为了防止旧 App 升级时数据库打开报错；
     * 未来可在下一次 schemaVersion bump 时 DROP TABLE。
     */
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

    /* =============================================================
     * FTS5 全文索引 — 字段来源表 & 同步时机
     * -------------------------------------------------------------
     * collections_fts.content_text 填充规则：
     *   title        <- collections.title
     *   author       <- collections.author
     *   note         <- collections.note
     *   content_text <- content/{id}.md（正文全文，每次 save/delete/重建索引时同步）
     *   category_json 和 tags_json 【不】入 FTS 字段。
     *
     * 同步时机：
     *   - CollectionRepositoryImpl.create/update/delete   → 手动 INSERT/UPDATE collections_fts
     *   - MaintenanceService.rebuildSearchIndex            → DROP + 重新填充所有行
     *   - DatabaseService.selfCheckAndRepair               → 对缺失 rowid 的做 INSERT 兜底
     *
     * 重要：CategoryRepositoryImpl.delete/rename 只改 collections.category_json，
     *       因为 category_json 不在 FTS 字段里，因此【无需】同步 FTS。
     * ============================================================= */
    await db.execute('''
      CREATE VIRTUAL TABLE collections_fts USING fts5(
        title,
        note,
        content_text
      )
    ''');
  }

  Future<({int ftsRowsInserted, int orphanDbRowsDeleted, List<String> errors})> selfCheckAndRepair([Database? dbParam]) async {
    final db = dbParam ?? await database;
    final errors = <String>[];
    var ftsRowsInserted = 0;
    var orphanDbRowsDeleted = 0;

    final rootDir = await StoragePathProvider().getRootDir();
    final metaDir = Directory(p.join(rootDir.path, AppConstants.metaDir));
    final contentDir = Directory(p.join(rootDir.path, AppConstants.contentDir));

    try {
      // FTS 仅对未软删除的行补写；软删除行的 FTS 应保持缺失（搜索不可见）。
      final liveRows = await db.rawQuery(
        'SELECT rowid, id, title, note FROM collections WHERE deleted_at IS NULL',
      );
      // 孤儿检测覆盖所有行（含已软删除），meta 文件缺失即视为孤儿。
      final allRows = await db.rawQuery('SELECT rowid, id FROM collections');

      // Step 1: FTS missing rowid补写（仅未删除行）
      for (final row in liveRows) {
        try {
          final rowid = row['rowid'] as int;
          final id = row['id'] as String;
          final title = (row['title'] as String?) ?? '';
          final note = (row['note'] as String?) ?? '';

          final ftsExists = await db.rawQuery(
            'SELECT rowid FROM collections_fts WHERE rowid = ?',
            [rowid],
          );
          if (ftsExists.isEmpty) {
            String contentText = '';
            try {
              final contentFile = File(p.join(contentDir.path, '$id.md'));
              if (await contentFile.exists()) {
                contentText = await contentFile.readAsString();
              }
            } catch (e) {
              errors.add('读取content文件失败(id=$id): $e');
            }
            await db.rawInsert(
              'INSERT INTO collections_fts(rowid, title, note, content_text) VALUES (?, ?, ?, ?)',
              [rowid, title, note, contentText],
            );
            ftsRowsInserted++;
          }
        } catch (e) {
          errors.add('FTS补写失败(row=${row['rowid']}): $e');
        }
      }

      // Step 2: 孤儿DB行（meta文件不存在）删除
      for (final row in allRows) {
        try {
          final id = row['id'] as String;
          final rowid = row['rowid'] as int;
          final metaFile = File(p.join(metaDir.path, '$id.json'));
          if (!await metaFile.exists()) {
            await db.delete('collections', where: 'id = ?', whereArgs: [id]);
            await db.delete('collections_fts', where: 'rowid = ?', whereArgs: [rowid]);
            orphanDbRowsDeleted++;
          }
        } catch (e) {
          errors.add('孤儿DB行删除失败(id=${row['id']}): $e');
        }
      }
    } catch (e) {
      errors.add('SelfCheck整体失败: $e');
    }

    return (
      ftsRowsInserted: ftsRowsInserted,
      orphanDbRowsDeleted: orphanDbRowsDeleted,
      errors: errors,
    );
  }
}
