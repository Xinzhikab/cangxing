import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:fav_app/core/utils/storage_path_provider.dart';
import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/features/collections/data/models/collection.dart';

class FileStorageService {
  final StoragePathProvider _pathProvider;

  FileStorageService(this._pathProvider);

  Future<void> saveMeta(Collection col) async {
    final metaDir = await _pathProvider.ensureDir(AppConstants.metaDir);
    final file = File(p.join(metaDir.path, '${col.id}.json'));
    await file.writeAsString(jsonEncode(col.toJson()));
  }

  Future<Collection?> loadMeta(String id) async {
    try {
      final metaDir = await _pathProvider.ensureDir(AppConstants.metaDir);
      final file = File(p.join(metaDir.path, '$id.json'));
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      return Collection.fromJson(jsonDecode(content));
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteMeta(String id) async {
    final metaDir = await _pathProvider.ensureDir(AppConstants.metaDir);
    final file = File(p.join(metaDir.path, '$id.json'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> saveContent(String id, String contentMd) async {
    final contentDir = await _pathProvider.ensureDir(AppConstants.contentDir);
    final file = File(p.join(contentDir.path, '$id.md'));
    await file.writeAsString(contentMd);
  }

  Future<String> loadContent(String id) async {
    final contentDir = await _pathProvider.ensureDir(AppConstants.contentDir);
    final file = File(p.join(contentDir.path, '$id.md'));
    if (!await file.exists()) return '';
    return await file.readAsString();
  }

  Future<void> deleteContent(String id) async {
    final contentDir = await _pathProvider.ensureDir(AppConstants.contentDir);
    final file = File(p.join(contentDir.path, '$id.md'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Directory> ensureImagesDir(String id) async {
    return await _pathProvider.ensureDir(p.join(AppConstants.imagesDir, id));
  }

  Future<String> saveImage(String id, String filename, List<int> bytes) async {
    final imgDir = await ensureImagesDir(id);
    final file = File(p.join(imgDir.path, filename));
    await file.writeAsBytes(bytes);
    return '${AppConstants.imagesDir}/$id/$filename';
  }

  Future<void> deleteImagesDir(String id) async {
    final imgDir = await ensureImagesDir(id);
    if (await imgDir.exists()) {
      await imgDir.delete(recursive: true);
    }
  }
}
