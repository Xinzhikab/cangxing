import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:fav_app/core/utils/storage_path_provider.dart';
import 'package:fav_app/features/collections/data/services/database_service.dart';
import 'package:fav_app/features/save/data/providers/transcription_providers.dart';

class MaintenanceService {
  final StoragePathProvider _storage;
  final DatabaseService _db;

  MaintenanceService(this._storage, this._db);

  /// 重建 FTS 全文索引：清空 collections_fts 后从每篇收藏的
  /// meta + content 文件重新灌入。索引损坏/搜索结果异常时使用。
  /// 仅重建未软删除的收藏，软删除项保持无 FTS 行（搜索不可见）。
  Future<int> rebuildSearchIndex() async {
    final db = await _db.database;
    final storageRoot = await _storage.getRootDir();

    final ids = (await db.query(
      'collections',
      columns: ['id'],
      where: 'deleted_at IS NULL',
    ))
        .map((row) => row['id'] as String)
        .toList();

    await db.delete('collections_fts');

    var count = 0;
    final batch = db.batch();
    for (final id in ids) {
      final metaFile = File(p.join(storageRoot.path, 'meta', '$id.json'));
      final contentFile = File(p.join(storageRoot.path, 'content', '$id.md'));
      String? title;
      String? note;
      if (await metaFile.exists()) {
        try {
          final lines = await metaFile.readAsString();
          final Map<String, dynamic> m = jsonDecode(lines);
          title = m['title'] as String? ?? '';
          note = m['note'] as String? ?? '';
        } catch (e, st) {
          debugPrint('[Maintenance] $e\n$st');
          title = '';
          note = '';
        }
      }
      var content = '';
      if (await contentFile.exists()) {
        try {
          content = await contentFile.readAsString();
        } catch (e, st) {
          debugPrint('[Maintenance] $e\n$st');
        }
      }
      batch.rawInsert(
        'INSERT INTO collections_fts(rowid, title, note, content_text) '
        'VALUES ((SELECT rowid FROM collections WHERE id=?), ?, ?, ?)',
        [id, title ?? '', note ?? '', content],
      );
      count++;
    }
    await batch.commit(noResult: true);
    return count;
  }

  /// 清理孤儿图片：images/{id}/ 目录在数据库已无对应收藏时整目录删除。
  /// 返回删除的目录数与释放的字节数。
  Future<(int dirs, int bytes)> cleanOrphanImages() async {
    final db = await _db.database;
    final storageRoot = await _storage.getRootDir();

    final ids = (await db.query('collections', columns: ['id']))
        .map((row) => row['id'] as String)
        .toSet();

    final imagesDir = Directory(p.join(storageRoot.path, 'images'));
    if (!await imagesDir.exists()) return (0, 0);

    var dirs = 0;
    var bytes = 0;
    await for (final entity in imagesDir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (ids.contains(name)) continue;

      await for (final f in entity.list(recursive: true, followLinks: false)) {
        if (f is File) {
          try {
            bytes += await f.length();
          } catch (e, st) {
            debugPrint('[Maintenance] $e\n$st');
          }
        }
      }
      try {
        await entity.delete(recursive: true);
        dirs++;
      } catch (e, st) {
        debugPrint('[Maintenance] $e\n$st');
      }
    }
    return (dirs, bytes);
  }
}

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService.instance;
});

final maintenanceServiceProvider = Provider<MaintenanceService>((ref) {
  return MaintenanceService(
    ref.read(storagePathProvider),
    ref.read(databaseServiceProvider),
  );
});
