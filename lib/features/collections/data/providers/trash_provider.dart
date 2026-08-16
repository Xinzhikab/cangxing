import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/collections/data/providers/collection_repository_provider.dart';
import 'package:fav_app/features/collections/data/providers/collections_refresh_provider.dart';

/// 回收站列表：返回所有已软删除的收藏（按删除时间倒序）。
/// watch collectionsRefreshProvider 以便在删除/恢复/清空后自动刷新。
final trashListProvider = FutureProvider<List<Collection>>((ref) async {
  ref.watch(collectionsRefreshProvider);
  final repo = ref.watch(collectionRepositoryProvider);
  return repo.listTrashed();
});
