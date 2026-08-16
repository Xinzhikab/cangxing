import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:fav_app/core/utils/storage_path_provider.dart';
import 'package:fav_app/features/collections/data/services/database_service.dart';

class MaintenanceService {
  /// 重建 FTS 全文索引：清空 collections_fts 后从每篇收藏的
  /// meta + content 文件重新灌入。索引损坏/搜索结果异常时使用。
  Future<int> rebuildSearchIndex() async {
    final db = await DatabaseService.instance.database;
    final storageRoot = await StoragePathProvider().getRootDir();

    final ids = (await db.query('collections', columns: ['id']))
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
        // 标题/笔记存在 meta JSON 里，读不到就退化用占位
        try {
          final lines = await metaFile.readAsString();
          title = RegExp(r'"title"\s*:\s*"((?:[^"\\]|\\.)*)"')
                  .firstMatch(lines)
                  ?.group(1) ??
              '';
          note = RegExp(r'"note"\s*:\s*"((?:[^"\\]|\\.)*)"')
                  .firstMatch(lines)
                  ?.group(1) ??
              '';
        } catch (_) {
          title = '';
          note = '';
        }
      }
      var content = '';
      if (await contentFile.exists()) {
        try {
          content = await contentFile.readAsString();
        } catch (_) {}
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
    final db = await DatabaseService.instance.database;
    final storageRoot = await StoragePathProvider().getRootDir();

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
          } catch (_) {}
        }
      }
      try {
        await entity.delete(recursive: true);
        dirs++;
      } catch (_) {}
    }
    return (dirs, bytes);
  }
}

final maintenanceServiceProvider = Provider<MaintenanceService>(
  (_) => MaintenanceService(),
);
