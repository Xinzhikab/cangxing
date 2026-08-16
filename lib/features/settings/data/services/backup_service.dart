import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/core/utils/storage_path_provider.dart';
import 'package:fav_app/features/collections/data/services/database_service.dart';

class BackupCancelledException implements Exception {
  const BackupCancelledException();
}

class BackupService {
  final StoragePathProvider paths;
  final DatabaseService db;

  BackupService(this.paths, this.db);

  /// 导出备份：先写入 `.tmp` 临时目录，写入 manifest 校验文件后，
  /// 再原子 rename 为目标目录。Windows 跨卷 rename 可能失败，
  /// 此时 fallback 到逐个拷贝。中途异常会清理半截临时目录，
  /// 避免留下不完整的备份被误用。
  Future<String> export() async {
    final outputDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择导出目录',
    );
    if (outputDir == null) throw const BackupCancelledException();

    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final target = Directory(p.join(outputDir, 'fav_backup_$stamp'));
    final tempDir = Directory('${target.path}.tmp');

    try {
      // 1. 先写到 .tmp 临时目录，避免半截备份被误用
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      await tempDir.create(recursive: true);

      final srcRoot = await paths.getRootDir();
      var entryCount = 0;
      var totalBytes = 0;

      // 2. 拷贝三个子目录到 tempDir，同时统计条目数与字节数
      for (final sub in ['meta', 'content', 'images']) {
        final s = Directory(p.join(srcRoot.path, sub));
        final d = Directory(p.join(tempDir.path, sub));
        if (await s.exists()) {
          final (cnt, bytes) = await _copyDirWithStats(s, d);
          entryCount += cnt;
          totalBytes += bytes;
        }
      }

      // 3. 拷贝数据库文件
      final dbPath = await DatabaseService.resolveDbPath();
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await dbFile.copy(p.join(tempDir.path, AppConstants.dbName));
        entryCount += 1;
        totalBytes += await dbFile.length();
      }

      // 4. 写 manifest 校验文件（条目数 + 总大小）
      final manifest = {
        'created_at': DateTime.now().toIso8601String(),
        'entry_count': entryCount,
        'total_bytes': totalBytes,
      };
      await File(p.join(tempDir.path, '.backup_manifest.json'))
          .writeAsString(jsonEncode(manifest));

      // 5. 原子 rename：temp → target
      //    Windows 上 Directory.rename 跨卷可能不支持，加 try/catch fallback
      if (target.existsSync()) await target.delete(recursive: true);
      try {
        await tempDir.rename(target.path);
      } catch (e) {
        debugPrint('[Backup] rename failed, fallback to copy: $e');
        await target.create(recursive: true);
        await _copyDir(tempDir, target);
        await tempDir.delete(recursive: true);
      }

      return target.path;
    } catch (e) {
      // 清理半截临时目录
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// 导入备份：若备份目录含 manifest，先校验条目数是否匹配，
  /// 不匹配（半截备份）直接抛错中止。无 manifest 的旧备份跳过校验。
  Future<void> doImport() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择要导入的备份目录',
    );
    if (dir == null) throw const BackupCancelledException();

    // 校验 manifest（若存在）：防止半截备份被导入
    final manifestFile = File(p.join(dir, '.backup_manifest.json'));
    if (manifestFile.existsSync()) {
      int? expectedCount;
      try {
        final manifest =
            jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
        expectedCount = manifest['entry_count'] as int?;
      } catch (e) {
        debugPrint('[Backup] manifest 解析失败，跳过校验: $e');
      }
      if (expectedCount != null) {
        final actualCount = _countBackupEntries(Directory(dir));
        if (actualCount != expectedCount) {
          throw Exception('备份文件不完整：期望 $expectedCount 个文件，实际 $actualCount 个');
        }
      }
    }

    final srcRoot = await paths.getRootDir();
    final oldDir = Directory(
      '${srcRoot.path}.importing_${DateTime.now().millisecondsSinceEpoch}',
    );
    try {
      await _copyDir(srcRoot, oldDir);
    } catch (e, st) {
      debugPrint('[Backup] $e\n$st');
    }

    for (final sub in ['meta', 'content', 'images']) {
      final s = Directory(p.join(dir, sub));
      final d = Directory(p.join(srcRoot.path, sub));
      if (await s.exists()) {
        if (await d.exists()) await d.delete(recursive: true);
        await _copyDir(s, d);
      }
    }

    final srcDb = File(p.join(dir, AppConstants.dbName));
    if (await srcDb.exists()) {
      final dstDb = File(await DatabaseService.resolveDbPath());
      await srcDb.copy(dstDb.path);
    }
  }

  Future<void> _copyDir(Directory src, Directory dst) async {
    await _copyDirWithStats(src, dst);
  }

  /// 递归拷贝目录，返回 (文件数, 总字节数)。
  Future<(int count, int bytes)> _copyDirWithStats(
    Directory src,
    Directory dst,
  ) async {
    await dst.create(recursive: true);
    var count = 0;
    var bytes = 0;
    await for (final e in src.list()) {
      if (e is File) {
        await e.copy(p.join(dst.path, p.basename(e.path)));
        count++;
        try {
          bytes += await e.length();
        } catch (_) {}
      } else if (e is Directory) {
        final (c, b) = await _copyDirWithStats(
          e,
          Directory(p.join(dst.path, p.basename(e.path))),
        );
        count += c;
        bytes += b;
      }
    }
    return (count, bytes);
  }

  /// 统计备份目录中的条目数（meta/content/images 子目录的文件 + db 文件）。
  /// 与 export 时写入 manifest 的口径一致，不含 .backup_manifest.json 本身。
  int _countBackupEntries(Directory backupDir) {
    var count = 0;
    for (final sub in ['meta', 'content', 'images']) {
      final d = Directory(p.join(backupDir.path, sub));
      if (d.existsSync()) {
        count += _countFilesRecursive(d);
      }
    }
    final dbFile = File(p.join(backupDir.path, AppConstants.dbName));
    if (dbFile.existsSync()) count += 1;
    return count;
  }

  int _countFilesRecursive(Directory dir) {
    var count = 0;
    try {
      for (final e in dir.listSync(followLinks: false)) {
        if (e is File) {
          count++;
        } else if (e is Directory) {
          count += _countFilesRecursive(e);
        }
      }
    } catch (_) {}
    return count;
  }
}
