import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:fav_app/features/collections/data/models/category.dart';
import 'package:fav_app/features/collections/data/services/database_service.dart';
import 'package:fav_app/features/collections/data/services/file_storage_service.dart';
import 'package:fav_app/features/collections/data/repositories/category_repository.dart';
import 'package:fav_app/features/collections/data/repositories/collection_repository.dart';

class CategoryRepositoryImpl implements CategoryRepository {
  final DatabaseService db;
  final CollectionRepository collectionRepo;
  final FileStorageService fileStorage;
  final Uuid _uuid = const Uuid();
  final Completer<void> _ready = Completer<void>();

  Future<void> get ready => _ready.future;

  CategoryRepositoryImpl({
    required this.db,
    required this.collectionRepo,
    required this.fileStorage,
  }) {
    _init();
  }

  Future<void> _init() async {
    try {
      await ensureDefaultCategory();
      _ready.complete();
    } catch (e) {
      _ready.completeError(e);
    }
  }

  @override
  Future<List<Category>> listAll() async {
    final database = await db.database;
    final rows = await database.query(
      'categories',
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return rows.map(_rowToCategory).toList();
  }

  @override
  Future<Category?> get(String id) async {
    final database = await db.database;
    final rows = await database.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToCategory(rows.first);
  }

  @override
  Future<Category> create(Category cat) async {
    final database = await db.database;
    final effectiveId = cat.id.isEmpty ? _uuid.v4() : cat.id;
    final effectiveCat = cat.id.isEmpty ? cat.copyWith(id: effectiveId) : cat;

    await database.insert('categories', _categoryToRow(effectiveCat));
    return effectiveCat;
  }

  @override
  Future<Category> update(Category cat) async {
    final database = await db.database;
    await database.update(
      'categories',
      _categoryToRow(cat),
      where: 'id = ?',
      whereArgs: [cat.id],
    );
    return cat;
  }

  @override
  Future<void> delete(String id) async {
    final database = await db.database;
    final deletedNames = <String>{};

    Future<void> deleteRecursively(String categoryId) async {
      final category = await get(categoryId);
      if (category != null) {
        deletedNames.add(category.name);
      }

      final children = await childrenOf(categoryId);
      for (final child in children) {
        await deleteRecursively(child.id);
      }

      await database.delete(
        'categories',
        where: 'id = ?',
        whereArgs: [categoryId],
      );
    }

    await deleteRecursively(id);

    // 受影响收藏回退「未分类」。原实现全量 list()（每篇读正文文件）
    // 并逐篇走完整 update（再读写正文 + 两次 FTS SQL），收藏多时
    // 串行 IO 达几十秒且无反馈，表现为删除卡死。
    // 现改为：SQL 定位 category 命中删除名的行，只改 meta 文件的
    // category 字段与 DB 的 category_json（分类不进 FTS，无需动索引）。
    if (deletedNames.isNotEmpty) {
      final likeClauses = deletedNames.map((n) => 'category_json LIKE ?').join(' OR ');
      final likeArgs = deletedNames.map((n) => '%"$n"%').toList();
      final rows = await database.query(
        'collections',
        columns: ['id'],
        where: likeClauses,
        whereArgs: likeArgs,
      );
      for (final row in rows) {
        final colId = row['id'] as String;
        final meta = await fileStorage.loadMeta(colId);
        if (meta == null) continue;
        final remained = meta.category.where((c) => !deletedNames.contains(c)).toList();
        final newCategory = remained.isEmpty ? ['未分类'] : remained;
        await fileStorage.saveMeta(meta.copyWith(category: newCategory));
        await database.update(
          'collections',
          {'category_json': jsonEncode(newCategory)},
          where: 'id = ?',
          whereArgs: [colId],
        );
      }
    }
  }

  @override
  Future<List<Category>> childrenOf(String? parentId) async {
    final database = await db.database;
    final List<Map<String, dynamic>> rows;
    if (parentId == null) {
      rows = await database.query(
        'categories',
        where: 'parent_id IS NULL',
        orderBy: 'sort_order ASC, created_at ASC',
      );
    } else {
      rows = await database.query(
        'categories',
        where: 'parent_id = ?',
        whereArgs: [parentId],
        orderBy: 'sort_order ASC, created_at ASC',
      );
    }
    return rows.map(_rowToCategory).toList();
  }

  @override
  Future<void> ensureDefaultCategory() async {
    final database = await db.database;
    final rows = await database.query(
      'categories',
      where: 'name = ? AND parent_id IS NULL',
      whereArgs: ['未分类'],
      limit: 1,
    );
    if (rows.isEmpty) {
      await database.insert('categories', {
        'id': _uuid.v4(),
        'name': '未分类',
        'parent_id': null,
        'sort_order': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Category _rowToCategory(Map<String, dynamic> row) {
    return Category(
      id: row['id'] as String,
      name: row['name'] as String,
      parentId: row['parent_id'] as String?,
      sortOrder: row['sort_order'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  Map<String, dynamic> _categoryToRow(Category cat) {
    return {
      'id': cat.id,
      'name': cat.name,
      'parent_id': cat.parentId,
      'sort_order': cat.sortOrder,
      'created_at': cat.createdAt.toIso8601String(),
    };
  }
}
