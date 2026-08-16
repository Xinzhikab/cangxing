import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fav_app/core/utils/storage_path_provider.dart';
import 'package:fav_app/features/collections/data/providers/collections_refresh_provider.dart';
import 'package:fav_app/features/collections/data/services/database_service.dart';
import 'package:fav_app/features/collections/data/services/file_storage_service.dart';
import 'package:fav_app/features/collections/data/repositories/category_repository.dart';
import 'package:fav_app/features/collections/data/repositories/category_repository_impl.dart';
import 'package:fav_app/features/collections/data/providers/collection_repository_provider.dart';

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  final collectionRepo = ref.watch(collectionRepositoryProvider);
  return CategoryRepositoryImpl(
    db: DatabaseService.instance,
    collectionRepo: collectionRepo,
    fileStorage: FileStorageService(StoragePathProvider()),
    onChanged: () => ref.read(collectionsRefreshProvider.notifier).bump(),
  );
});
