import 'dart:io';

import 'package:file_picker/file_picker.dart';
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

  Future<String> export() async {
    final outputDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择导出目录',
    );
    if (outputDir == null) throw const BackupCancelledException();

    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final target = Directory(p.join(outputDir, 'fav_backup_$stamp'));
    await target.create(recursive: true);

    final srcRoot = await paths.getRootDir();

    for (final sub in ['meta', 'content', 'images']) {
      final s = Directory(p.join(srcRoot.path, sub));
      final d = Directory(p.join(target.path, sub));
      if (await s.exists()) await _copyDir(s, d);
    }

    final dbPath = await DatabaseService.resolveDbPath();
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      await dbFile.copy(p.join(target.path, AppConstants.dbName));
    }

    return target.path;
  }

  Future<void> doImport() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择要导入的备份目录',
    );
    if (dir == null) throw const BackupCancelledException();

    final srcRoot = await paths.getRootDir();
    final oldDir = Directory(
      '${srcRoot.path}.importing_${DateTime.now().millisecondsSinceEpoch}',
    );
    try {
      await _copyDir(srcRoot, oldDir);
    } catch (_) {}

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
    await dst.create(recursive: true);
    await for (final e in src.list()) {
      if (e is File) {
        await e.copy(p.join(dst.path, p.basename(e.path)));
      } else if (e is Directory) {
        await _copyDir(e, Directory(p.join(dst.path, p.basename(e.path))));
      }
    }
  }
}
