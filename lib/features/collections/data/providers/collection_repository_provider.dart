import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fav_app/core/utils/storage_path_provider.dart';
import 'package:fav_app/features/collections/data/models/collection_note.dart';
import 'package:fav_app/features/collections/data/services/database_service.dart';
import 'package:fav_app/features/collections/data/services/file_storage_service.dart';
import 'package:fav_app/features/collections/data/repositories/collection_repository.dart';
import 'package:fav_app/features/collections/data/repositories/collection_repository_impl.dart';

final collectionRepositoryProvider = Provider<CollectionRepository>((ref) {
  return CollectionRepositoryImpl(
    db: DatabaseService.instance,
    fileStorage: FileStorageService(StoragePathProvider()),
  );
});

/// 某篇文章的笔记列表（评论区模式），按时间倒序。
final collectionNotesProvider =
    FutureProvider.family<List<CollectionNote>, String>(
  (ref, collectionId) =>
      ref.watch(collectionRepositoryProvider).listNotes(collectionId),
);
