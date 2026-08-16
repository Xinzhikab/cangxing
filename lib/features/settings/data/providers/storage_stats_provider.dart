import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:fav_app/core/utils/storage_path_provider.dart';
import 'package:fav_app/features/collections/data/services/database_service.dart';

class StorageStats {
  final int collectionCount;
  final int totalSizeBytes;
  final int metaSizeBytes;
  final int contentSizeBytes;
  final int imagesSizeBytes;

  StorageStats({
    required this.collectionCount,
    required this.totalSizeBytes,
    required this.metaSizeBytes,
    required this.contentSizeBytes,
    required this.imagesSizeBytes,
  });

  String get totalSizeFormatted {
    int bytes = totalSizeBytes;
    if (bytes < 1024) return '$bytes B';
    bytes = bytes ~/ 1024;
    if (bytes < 1024) return '$bytes KB';
    bytes = bytes ~/ 1024;
    if (bytes < 1024) return '$bytes MB';
    bytes = bytes ~/ 1024;
    return '$bytes GB';
  }
}

Future<int> _dirSize(Directory dir) async {
  int total = 0;
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      try {
        total += await entity.length();
      } catch (_) {}
    }
  }
  return total;
}

final storageStatsProvider = FutureProvider<StorageStats>((ref) async {
  final rootDir = await StoragePathProvider().getRootDir();

  int metaSize = 0;
  int contentSize = 0;
  int imagesSize = 0;
  int totalSize = 0;

  final metaDir = Directory(p.join(rootDir.path, 'meta'));
  final contentDir = Directory(p.join(rootDir.path, 'content'));
  final imagesDir = Directory(p.join(rootDir.path, 'images'));

  if (await metaDir.exists()) {
    metaSize = await _dirSize(metaDir);
  }
  if (await contentDir.exists()) {
    contentSize = await _dirSize(contentDir);
  }
  if (await imagesDir.exists()) {
    imagesSize = await _dirSize(imagesDir);
  }
  if (await rootDir.exists()) {
    totalSize = await _dirSize(rootDir);
  }

  final db = await DatabaseService.instance.database;
  final result = await db.rawQuery('SELECT COUNT(*) as count FROM collections');
  final collectionCount = Sqflite.firstIntValue(result) ?? 0;

  return StorageStats(
    collectionCount: collectionCount,
    totalSizeBytes: totalSize,
    metaSizeBytes: metaSize,
    contentSizeBytes: contentSize,
    imagesSizeBytes: imagesSize,
  );
});
