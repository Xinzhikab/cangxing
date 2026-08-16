import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/collections/data/models/collection_note.dart';
import 'package:fav_app/features/collections/data/services/database_service.dart';
import 'package:fav_app/features/collections/data/services/file_storage_service.dart';
import 'package:fav_app/features/collections/data/repositories/collection_repository.dart';

class CollectionRepositoryImpl implements CollectionRepository {
  final DatabaseService db;
  final FileStorageService fileStorage;

  CollectionRepositoryImpl({required this.db, required this.fileStorage});

  @override
  Future<List<Collection>> list({
    List<String>? categoryPath,
    String? platform,
    String? author,
    String? status,
    String? tag,
    String? sortBy,
    bool descending = true,
  }) async {
    final database = await db.database;
    final where = <String>[];
    final args = <dynamic>[];

    if (categoryPath != null && categoryPath.isNotEmpty) {
      where.add('category_json LIKE ?');
      args.add('${jsonEncode(categoryPath).replaceAll(']', '')}%');
    }
    if (platform != null) {
      where.add('source_platform = ?');
      args.add(platform);
    }
    if (author != null) {
      where.add('author = ?');
      args.add(author);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status);
    }
    if (tag != null && tag.isNotEmpty) {
      where.add('tags LIKE ?');
      args.add('%"$tag"%');
    }

    final orderBy = '${_mapSortColumn(sortBy ?? 'collected_at')} ${descending ? 'DESC' : 'ASC'}';
    final whereClause = where.isEmpty ? null : where.join(' AND ');

    final rows = await database.query(
      'collections',
      where: whereClause,
      whereArgs: args,
      orderBy: orderBy,
    );

    return Future.wait(rows.map(_rowToCollection));
  }

  @override
  Future<Collection?> get(String id) async {
    final meta = await fileStorage.loadMeta(id);
    if (meta == null) return null;
    final contentMd = await fileStorage.loadContent(id);
    return meta.copyWith(contentMd: contentMd);
  }

  @override
  Future<Collection> create(Collection col, {required String contentMd}) async {
    await fileStorage.saveMeta(col);
    await fileStorage.saveContent(col.id, contentMd);

    final database = await db.database;
    await database.insert('collections', _collectionToRow(col));

    await database.rawInsert(
      'INSERT INTO collections_fts(rowid, title, note, content_text) VALUES ((SELECT rowid FROM collections WHERE id=?), ?, ?, ?)',
      [col.id, col.title, col.note, contentMd],
    );

    return col.copyWith(contentMd: contentMd);
  }

  @override
  Future<Collection> update(Collection col) async {
    await fileStorage.saveMeta(col);
    var effectiveContentMd = col.contentMd;
    if (col.contentMd.isNotEmpty) {
      await fileStorage.saveContent(col.id, col.contentMd);
    } else {
      effectiveContentMd = await fileStorage.loadContent(col.id);
    }

    final database = await db.database;
    await database.update(
      'collections',
      _collectionToRow(col),
      where: 'id = ?',
      whereArgs: [col.id],
    );

    await database.rawDelete(
      'DELETE FROM collections_fts WHERE rowid IN (SELECT rowid FROM collections WHERE id=?)',
      [col.id],
    );
    await database.rawInsert(
      'INSERT INTO collections_fts(rowid, title, note, content_text) VALUES ((SELECT rowid FROM collections WHERE id=?), ?, ?, ?)',
      [col.id, col.title, col.note, effectiveContentMd],
    );

    return col.copyWith(contentMd: effectiveContentMd);
  }

  @override
  Future<void> delete(String id) async {
    final database = await db.database;
    await database.rawDelete(
      'DELETE FROM collections_fts WHERE rowid IN (SELECT rowid FROM collections WHERE id=?)',
      [id],
    );
    await database.delete(
      'collections',
      where: 'id = ?',
      whereArgs: [id],
    );
    await database.delete(
      'collection_notes',
      where: 'collection_id = ?',
      whereArgs: [id],
    );

    await fileStorage.deleteMeta(id);
    await fileStorage.deleteContent(id);
    await fileStorage.deleteImagesDir(id);
  }

  @override
  Future<List<Collection>> search(String keyword, {int limit = 50}) async {
    final database = await db.database;
    final kw = keyword.trim();
    if (kw.isEmpty) return [];

    // FTS 前缀匹配：每个词加 *（搜 "wi" 可命中 "win"），多词 AND。
    // 注意：FTS5 MATCH 参数里不能带未转义引号，剥掉即可
    final terms = kw
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll('"', ''))
        .where((t) => t.isNotEmpty)
        .map((t) => '$t*')
        .join(' ');

    final rows = <Map<String, Object?>>[];
    final seen = <String>{};

    if (terms.isNotEmpty) {
      final ftsRows = await database.rawQuery(
        'SELECT c.* FROM collections c JOIN collections_fts f ON f.rowid = (SELECT rowid FROM collections WHERE id = c.id) '
        'WHERE collections_fts MATCH ? ORDER BY rank LIMIT ?',
        [terms, limit],
      );
      for (final r in ftsRows) {
        if (seen.add(r['id'] as String)) rows.add(r);
      }
    }

    // LIKE 兜底：unicode61 分词器把连续中文当一整个 token，
    // 中文词搜索 FTS 命中不了，靠标题/作者/标签 LIKE 补
    final like = '%$kw%';
    final likeRows = await database.rawQuery(
      'SELECT * FROM collections WHERE title LIKE ? OR author LIKE ? '
      'OR tags LIKE ? OR note LIKE ? LIMIT ?',
      [like, like, like, like, limit],
    );
    for (final r in likeRows) {
      if (seen.add(r['id'] as String)) rows.add(r);
    }

    return Future.wait(rows.take(limit).map(_rowToCollection));
  }

  @override
  Future<List<Map<String, int>>> groupByPlatform() async {
    return _groupBy('source_platform');
  }

  @override
  Future<List<Map<String, int>>> groupByAuthor() async {
    return _groupBy('author');
  }

  @override
  Future<List<Map<String, int>>> groupByStatus() async {
    // 已读/未读功能已移除：状态筛选只保留「想学 / 已完成」
    return (await _groupBy('status'))
        .where((m) => m.keys.first == 'learning' || m.keys.first == 'done')
        .toList();
  }

  Future<List<Map<String, int>>> _groupBy(String column) async {
    final database = await db.database;
    final rows = await database.rawQuery(
      'SELECT $column AS key, COUNT(*) AS count FROM collections GROUP BY $column ORDER BY count DESC',
    );
    return rows.map((r) {
      final key = r['key'] as String? ?? '';
      final count = r['count'] as int? ?? 0;
      return {key: count};
    }).toList();
  }

  String _mapSortColumn(String sortBy) {
    switch (sortBy) {
      case 'title':
        return 'title';
      case 'collected_at':
        return 'collected_at';
      case 'published_at':
        return 'published_at';
      case 'author':
        return 'author';
      case 'review_due_at':
        return 'review_due_at';
      default:
        return 'collected_at';
    }
  }

  Map<String, dynamic> _collectionToRow(Collection col) {
    return {
      'id': col.id,
      'title': col.title,
      'type': col.type,
      'source_platform': col.sourcePlatform,
      'source_url': col.sourceUrl,
      'author': col.author,
      'published_at': col.publishedAt?.toIso8601String(),
      'collected_at': col.collectedAt.toIso8601String(),
      'category_json': jsonEncode(col.category),
      'images_json': jsonEncode(col.images),
      'note': col.note,
      'status': col.status,
      'review_due_at': col.reviewDueAt?.toIso8601String(),
      'tags': jsonEncode(col.tags),
    };
  }

  Future<Collection> _rowToCollection(Map<String, dynamic> row) async {
    final col = Collection(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      type: row['type'] as String? ?? '',
      sourcePlatform: row['source_platform'] as String? ?? '',
      sourceUrl: row['source_url'] as String? ?? '',
      author: row['author'] as String? ?? '',
      publishedAt: row['published_at'] != null
          ? DateTime.tryParse(row['published_at'] as String)
          : null,
      collectedAt: DateTime.parse(row['collected_at'] as String),
      category: (jsonDecode(row['category_json'] as String? ?? '[]') as List<dynamic>).cast<String>(),
      images: (jsonDecode(row['images_json'] as String? ?? '[]') as List<dynamic>).cast<String>(),
      note: row['note'] as String? ?? '',
      status: row['status'] as String? ?? '',
      reviewDueAt: row['review_due_at'] != null
          ? DateTime.tryParse(row['review_due_at'] as String)
          : null,
      tags: ((jsonDecode(row['tags'] as String? ?? '[]') as List<dynamic>))
          .whereType<String>()
          .toList(growable: false),
      rawInput: '',
    );
    final contentMd = await fileStorage.loadContent(col.id);
    return col.copyWith(contentMd: contentMd);
  }

  // ---------- 评论区模式（多条笔记） ----------

  @override
  Future<List<CollectionNote>> listNotes(String collectionId) async {
    final database = await db.database;
    final rows = await database.query(
      'collection_notes',
      where: 'collection_id = ?',
      whereArgs: [collectionId],
      orderBy: 'created_at DESC',
    );
    return rows.map(CollectionNote.fromRow).toList(growable: false);
  }

  @override
  Future<CollectionNote> addNote(CollectionNote note) async {
    final database = await db.database;
    await database.insert('collection_notes', note.toRow());
    await _syncNoteForSearch(note.collectionId, note.content);
    return note;
  }

  @override
  Future<void> deleteNote(String id) async {
    final database = await db.database;
    final rows = await database.query(
      'collection_notes',
      columns: ['collection_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    await database.delete(
      'collection_notes',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isNotEmpty) {
      final collectionId = rows.first['collection_id'] as String;
      // 同步 note 列（供全文搜索）：取剩余最新一条，无则清空
      final latest = await database.rawQuery(
        'SELECT content FROM collection_notes WHERE collection_id = ? '
        'ORDER BY created_at DESC LIMIT 1',
        [collectionId],
      );
      final text =
          latest.isNotEmpty ? latest.first['content'] as String? ?? '' : '';
      await _syncNoteForSearch(collectionId, text);
    }
  }

  /// 笔记变更时同步 collections.note 列与 FTS 索引，保证全文搜索仍能命中笔记。
  Future<void> _syncNoteForSearch(String collectionId, String noteText) async {
    final database = await db.database;
    await database.update(
      'collections',
      {'note': noteText},
      where: 'id = ?',
      whereArgs: [collectionId],
    );
    final contentMd = await fileStorage.loadContent(collectionId);
    await database.rawDelete(
      'DELETE FROM collections_fts WHERE rowid IN '
      '(SELECT rowid FROM collections WHERE id=?)',
      [collectionId],
    );
    await database.rawInsert(
      'INSERT INTO collections_fts(rowid, title, note, content_text) '
      'VALUES ((SELECT rowid FROM collections WHERE id=?), '
      '(SELECT title FROM collections WHERE id=?), ?, ?)',
      [collectionId, collectionId, noteText, contentMd],
    );
  }

  // ---------- 标签注册表（手动创建的标签，供 AI 保存时优先关联） ----------

  @override
  Future<List<String>> listTags() async {
    final database = await db.database;
    final rows =
        await database.query('tags', columns: ['name'], orderBy: 'name');
    return rows.map((r) => r['name'] as String).toList(growable: false);
  }

  @override
  Future<void> addTag(String name) async {
    final t = _cleanTagName(name);
    if (t.isEmpty) return;
    final database = await db.database;
    await database.insert(
      'tags',
      {'name': t, 'created_at': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> deleteTag(String name) async {
    final database = await db.database;
    await database.transaction((txn) async {
      await txn.delete('tags', where: 'name = ?', whereArgs: [name]);
      final rows = await txn.query('collections', columns: ['id', 'tags']);
      for (final row in rows) {
        final tags = (jsonDecode(row['tags'] as String? ?? '[]') as List<dynamic>)
            .whereType<String>()
            .toList();
        if (tags.remove(name)) {
          await txn.update(
            'collections',
            {'tags': jsonEncode(tags)},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
    });
  }

  @override
  Future<void> renameTag(String oldName, String newName) async {
    final t = _cleanTagName(newName);
    if (t.isEmpty || t == oldName) return;
    final database = await db.database;
    await database.transaction((txn) async {
      await txn.delete('tags', where: 'name = ?', whereArgs: [oldName]);
      await txn.insert(
        'tags',
        {'name': t, 'created_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      final rows = await txn.query('collections', columns: ['id', 'tags']);
      for (final row in rows) {
        final tags =
            (jsonDecode(row['tags'] as String? ?? '[]') as List<dynamic>)
                .whereType<String>()
                .toSet();
        if (tags.remove(oldName)) {
          tags.add(t);
          await txn.update(
            'collections',
            {'tags': jsonEncode(tags.toList())},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
    });
  }

  /// 规范化标签名：去空白、去掉会破坏 LIKE 匹配的引号，限制长度。
  static String _cleanTagName(String name) {
    var t = name
        .trim()
        .replaceAll('"', '')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (t.length > 24) {
      t = t.substring(0, 24).trim();
    }
    return t;
  }
}
