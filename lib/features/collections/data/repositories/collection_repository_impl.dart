import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/collections/data/models/collection_note.dart';
import 'package:fav_app/features/collections/data/services/database_service.dart';
import 'package:fav_app/features/collections/data/services/file_storage_service.dart';
import 'package:fav_app/features/collections/data/repositories/collection_repository.dart';

class CollectionRepositoryImpl implements CollectionRepository {
  final DatabaseService db;
  final FileStorageService fileStorage;
  final void Function()? onChanged;

  CollectionRepositoryImpl({
    required this.db,
    required this.fileStorage,
    this.onChanged,
  });

  @override
  Future<List<Collection>> list({
    List<String>? categoryPath,
    SourcePlatform? platform,
    String? author,
    CollectionStatus? status,
    String? tag,
    CollectionSortField sortBy = CollectionSortField.collectedAt,
    bool descending = true,
    bool pinnedOnly = false,
  }) async {
    final database = await db.database;
    final where = <String>['deleted_at IS NULL'];
    final args = <dynamic>[];

    if (categoryPath != null && categoryPath.isNotEmpty) {
      where.add('category_json LIKE ?');
      args.add('${jsonEncode(categoryPath).replaceAll(']', '')}%');
    }
    final platformSql = CollectionEnums.platformToSql(platform);
    if (platformSql != null) {
      where.add('source_platform = ?');
      args.add(platformSql);
    }
    if (author != null) {
      where.add('author = ?');
      args.add(author);
    }
    final statusSql = CollectionEnums.statusToSql(status);
    if (statusSql != null) {
      where.add('status = ?');
      args.add(statusSql);
    }
    if (tag != null && tag.isNotEmpty) {
      where.add('tags LIKE ?');
      args.add('%"$tag"%');
    }
    if (pinnedOnly) {
      where.add('pinned_at IS NOT NULL');
    }

    final baseOrder = '${_mapSortColumn(sortBy)} ${descending ? 'DESC' : 'ASC'}';
    final orderBy =
        'CASE WHEN pinned_at IS NOT NULL THEN 0 ELSE 1 END ASC, pinned_at DESC, $baseOrder';
    final whereClause = where.join(' AND ');

    final rows = await database.query(
      'collections',
      where: whereClause,
      whereArgs: args,
      orderBy: orderBy,
    );

    return rows.map(_rowToCollectionMetaOnly).toList();
  }

  @override
  Future<List<Collection>> listMetaOnly({
    List<String>? categoryPath,
    SourcePlatform? platform,
    String? author,
    CollectionStatus? status,
    String? tag,
    CollectionSortField sortBy = CollectionSortField.collectedAt,
    bool descending = true,
    bool pinnedOnly = false,
  }) async {
    final database = await db.database;
    final where = <String>['deleted_at IS NULL'];
    final args = <dynamic>[];

    if (categoryPath != null && categoryPath.isNotEmpty) {
      where.add('category_json LIKE ?');
      args.add('${jsonEncode(categoryPath).replaceAll(']', '')}%');
    }
    final platformSql = CollectionEnums.platformToSql(platform);
    if (platformSql != null) {
      where.add('source_platform = ?');
      args.add(platformSql);
    }
    if (author != null) {
      where.add('author = ?');
      args.add(author);
    }
    final statusSql = CollectionEnums.statusToSql(status);
    if (statusSql != null) {
      where.add('status = ?');
      args.add(statusSql);
    }
    if (tag != null && tag.isNotEmpty) {
      where.add('tags LIKE ?');
      args.add('%"$tag"%');
    }
    if (pinnedOnly) {
      where.add('pinned_at IS NOT NULL');
    }

    final baseOrder = '${_mapSortColumn(sortBy)} ${descending ? 'DESC' : 'ASC'}';
    final orderBy =
        'CASE WHEN pinned_at IS NOT NULL THEN 0 ELSE 1 END ASC, pinned_at DESC, $baseOrder';
    final whereClause = where.join(' AND ');

    final rows = await database.query(
      'collections',
      where: whereClause,
      whereArgs: args,
      orderBy: orderBy,
    );

    return rows.map(_rowToCollectionMetaOnly).toList();
  }

  @override
  Future<Collection?> get(String id) async {
    final database = await db.database;
    // 已软删除的收藏不对外返回（除非走回收站路径）。
    final rows = await database.query(
      'collections',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
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

    onChanged?.call();
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

    onChanged?.call();
    return col.copyWith(contentMd: effectiveContentMd);
  }

  @override
  Future<void> delete(String id) async {
    final database = await db.database;
    // 软删除：仅打 deleted_at 标记，从搜索结果移除（删 FTS 行）。
    // 不动 collection_notes / meta / content / images 文件，便于恢复。
    await database.update(
      'collections',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
    await database.rawDelete(
      'DELETE FROM collections_fts WHERE rowid IN (SELECT rowid FROM collections WHERE id=?)',
      [id],
    );
    onChanged?.call();
  }

  @override
  Future<List<Collection>> listTrashed() async {
    final database = await db.database;
    final rows = await database.query(
      'collections',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    );
    return rows.map(_rowToCollectionMetaOnly).toList();
  }

  @override
  Future<void> restore(String id) async {
    final database = await db.database;
    await database.update(
      'collections',
      {'deleted_at': null},
      where: 'id = ?',
      whereArgs: [id],
    );
    // 重建 FTS 索引，使该收藏重新可被搜索。
    final rows = await database.query(
      'collections',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final row = rows.first;
      final title = (row['title'] as String?) ?? '';
      final note = (row['note'] as String?) ?? '';
      final contentMd = await fileStorage.loadContent(id);
      await database.rawDelete(
        'DELETE FROM collections_fts WHERE rowid IN (SELECT rowid FROM collections WHERE id=?)',
        [id],
      );
      await database.rawInsert(
        'INSERT INTO collections_fts(rowid, title, note, content_text) '
        'VALUES ((SELECT rowid FROM collections WHERE id=?), ?, ?, ?)',
        [id, title, note, contentMd],
      );
    }
    onChanged?.call();
  }

  @override
  Future<void> permanentDelete(String id) async {
    final database = await db.database;
    // 先删 FTS（通过子查询取 rowid，避免依赖已删行）
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
    // 再删物理文件
    await fileStorage.deleteMeta(id);
    await fileStorage.deleteContent(id);
    await fileStorage.deleteImagesDir(id);
    onChanged?.call();
  }

  @override
  Future<void> emptyTrash() async {
    final trashed = await listTrashed();
    await Future.wait(trashed.map((c) => permanentDelete(c.id)));
  }

  @override
  Future<void> togglePin(String id) async {
    final database = await db.database;
    final row = await database.query(
      'collections',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (row.isEmpty) return;
    final wasPinned = row.first['pinned_at'] != null;
    await database.update(
      'collections',
      {
        'pinned_at':
            wasPinned ? null : DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    onChanged?.call();
  }

  @override
  Future<void> setPinnedBatch(List<String> ids, {required bool pinned}) async {
    if (ids.isEmpty) return;
    final database = await db.database;
    final val = pinned ? DateTime.now().millisecondsSinceEpoch : null;
    final placeholders = List.filled(ids.length, '?').join(',');
    await database.update(
      'collections',
      {'pinned_at': val},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    onChanged?.call();
  }

  @override
  Future<List<Collection>> search(String keyword, {int limit = 50}) async {
    final database = await db.database;
    final kw = keyword.trim();
    if (kw.isEmpty) return [];

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
        'WHERE collections_fts MATCH ? AND c.deleted_at IS NULL ORDER BY rank LIMIT ?',
        [terms, limit],
      );
      for (final r in ftsRows) {
        if (seen.add(r['id'] as String)) rows.add(r);
      }
    }

    if (kw.length < 3) {
      final like = '%$kw%';
      final likeRows = await database.rawQuery(
        'SELECT * FROM collections WHERE deleted_at IS NULL AND (title LIKE ? OR author LIKE ? OR note LIKE ?) LIMIT ?',
        [like, like, like, limit],
      );
      for (final r in likeRows) {
        if (seen.add(r['id'] as String)) rows.add(r);
      }
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
    final learning = CollectionEnums.statusValues[CollectionStatus.learning]!;
    final done = CollectionEnums.statusValues[CollectionStatus.done]!;
    return (await _groupBy('status'))
        .where((m) => m.keys.first == learning || m.keys.first == done)
        .toList();
  }

  Future<List<Map<String, int>>> _groupBy(String column) async {
    final database = await db.database;
    final rows = await database.rawQuery(
      'SELECT $column AS key, COUNT(*) AS count FROM collections '
      'WHERE deleted_at IS NULL GROUP BY $column ORDER BY count DESC',
    );
    return rows.map((r) {
      final key = r['key'] as String? ?? '';
      final count = r['count'] as int? ?? 0;
      return {key: count};
    }).toList();
  }

  String _mapSortColumn(CollectionSortField f) => CollectionEnums.sortToSql(f);

  Map<String, dynamic> _collectionToRow(Collection col) {
    final typeEnum = CollectionEnums.typeFromSql(col.type);
    final statusEnum = CollectionEnums.statusFromSql(col.status);
    final platformEnum = CollectionEnums.platformFromSql(col.sourcePlatform);
    return {
      'id': col.id,
      'title': col.title,
      'type': CollectionEnums.typeToSql(typeEnum) ??
          CollectionEnums.typeToSql(CollectionType.article)!,
      'source_platform': CollectionEnums.platformToSql(platformEnum) ??
          CollectionEnums.platformToSql(SourcePlatform.other)!,
      'source_url': col.sourceUrl,
      'author': col.author,
      'published_at': col.publishedAt?.toIso8601String(),
      'collected_at': col.collectedAt.toIso8601String(),
      'category_json': jsonEncode(col.category),
      'images_json': jsonEncode(col.images),
      'note': col.note,
      'status': CollectionEnums.statusToSql(statusEnum) ??
          CollectionEnums.statusToSql(CollectionStatus.unread)!,
      'review_due_at': col.reviewDueAt?.toIso8601String(),
      'tags': jsonEncode(col.tags),
      'pinned_at': col.pinnedAt,
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
      deletedAt: row['deleted_at'] as int?,
      pinnedAt: row['pinned_at'] as int?,
    );
    final contentMd = await fileStorage.loadContent(col.id);
    return col.copyWith(contentMd: contentMd);
  }

  Collection _rowToCollectionMetaOnly(Map<String, dynamic> row) {
    return Collection(
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
      contentMd: '',
      deletedAt: row['deleted_at'] as int?,
      pinnedAt: row['pinned_at'] as int?,
    );
  }

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
    onChanged?.call();
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
      final latest = await database.rawQuery(
        'SELECT content FROM collection_notes WHERE collection_id = ? '
        'ORDER BY created_at DESC LIMIT 1',
        [collectionId],
      );
      final text =
          latest.isNotEmpty ? latest.first['content'] as String? ?? '' : '';
      await _syncNoteForSearch(collectionId, text);
    }
    onChanged?.call();
  }

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

  @override
  Future<List<String>> listTags() async {
    final database = await db.database;
    final rows =
        await database.query('tags', columns: ['name'], orderBy: 'name');
    return rows.map((r) => r['name'] as String).toList(growable: false);
  }

  @override
  Future<void> addTag(String name) async {}

  @override
  Future<void> deleteTag(String name) async {
    final database = await db.database;
    await database.transaction((txn) async {
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
    onChanged?.call();
  }

  @override
  Future<void> renameTag(String oldName, String newName) async {
    final t = _cleanTagName(newName);
    if (t.isEmpty || t == oldName) return;
    final database = await db.database;
    await database.transaction((txn) async {
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
    onChanged?.call();
  }

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
