import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fav_app/core/utils/storage_path_provider.dart';
import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/collections/data/providers/collection_repository_provider.dart';

final collectionDetailProvider =
    FutureProvider.autoDispose.family<Collection?, String>((ref, id) async {
  return ref.watch(collectionRepositoryProvider).get(id);
});

final storageDirRootProvider = FutureProvider<String>((ref) async {
  final d = await StoragePathProvider().getRootDir();
  return d.path;
});
