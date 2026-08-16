import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/collections/data/providers/collection_repository_provider.dart';
import 'package:fav_app/features/collections/data/repositories/collection_repository.dart';

class CollectionsFilter {
  final String keyword;
  final List<String>? categoryPath;
  final String? platform;
  final String? author;
  final String? status;
  final String sortBy;
  final bool descending;

  const CollectionsFilter({
    this.keyword = '',
    this.categoryPath,
    this.platform,
    this.author,
    this.status,
    this.sortBy = 'collected_at',
    this.descending = true,
  });

  CollectionsFilter copyWith({
    String? keyword,
    List<String>? categoryPath,
    String? platform,
    String? author,
    String? status,
    String? sortBy,
    bool? descending,
  }) {
    return CollectionsFilter(
      keyword: keyword ?? this.keyword,
      categoryPath: categoryPath ?? this.categoryPath,
      platform: platform ?? this.platform,
      author: author ?? this.author,
      status: status ?? this.status,
      sortBy: sortBy ?? this.sortBy,
      descending: descending ?? this.descending,
    );
  }
}

class CollectionsListController extends StateNotifier<AsyncValue<List<Collection>>> {
  final CollectionRepository repo;
  final CollectionsFilter filter;

  CollectionsListController(this.repo, this.filter)
      : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      if (filter.keyword.trim().isNotEmpty) return repo.search(filter.keyword);
      return repo.list(
        categoryPath: filter.categoryPath,
        platform: filter.platform,
        author: filter.author,
        status: filter.status,
        sortBy: filter.sortBy,
        descending: filter.descending,
      );
    });
  }
}

final collectionsFilterProvider =
    StateProvider<CollectionsFilter>((ref) => const CollectionsFilter(
          keyword: '',
          sortBy: 'collected_at',
          descending: true,
        ));

final collectionsListProvider =
    StateNotifierProvider<CollectionsListController, AsyncValue<List<Collection>>>((ref) {
  final filter = ref.watch(collectionsFilterProvider);
  return CollectionsListController(ref.watch(collectionRepositoryProvider), filter);
});

final groupStatsProvider =
    FutureProvider<Map<String, List<Map<String, int>>>>((ref) async {
  final repo = ref.watch(collectionRepositoryProvider);
  return {
    'platforms': await repo.groupByPlatform(),
    'authors': await repo.groupByAuthor(),
    'statuses': await repo.groupByStatus(),
  };
});

/// 全部收藏的 AI 标签聚合（含每个标签的文章数）。
/// 合并标签注册表中手动创建的标签（即使暂未被任何文章使用也展示，计数为 0）。
final allTagsProvider = FutureProvider<Map<String, int>>((ref) async {
  final repo = ref.watch(collectionRepositoryProvider);
  final cols = await repo.list();
  final counts = <String, int>{};
  for (final c in cols) {
    for (final t in c.tags) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
  }
  final registered = await repo.listTags();
  for (final t in registered) {
    counts.putIfAbsent(t, () => 0);
  }
  return counts;
});

/// 分类浏览的文章列表筛选条件。
class CategoryArticlesFilter {
  final List<String> categoryPath;
  final String? platform;
  final String? author;
  final String? tag;

  const CategoryArticlesFilter({
    this.categoryPath = const [],
    this.platform,
    this.author,
    this.tag,
  });

  @override
  bool operator ==(Object other) {
    if (other is! CategoryArticlesFilter) return false;
    if (other.platform != platform) return false;
    if (other.author != author) return false;
    if (other.tag != tag) return false;
    if (other.categoryPath.length != categoryPath.length) return false;
    for (var i = 0; i < categoryPath.length; i++) {
      if (other.categoryPath[i] != categoryPath[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        platform,
        author,
        tag,
        Object.hashAll(categoryPath),
      );
}

/// 分类浏览用的文章列表：按文件夹路径 / 平台 / 作者 / 标签筛选。
final categoryArticlesProvider = FutureProvider.family<
    List<Collection>,
    CategoryArticlesFilter>(
  (ref, f) async {
    final repo = ref.watch(collectionRepositoryProvider);
    return repo.list(
      categoryPath: f.categoryPath,
      platform: f.platform,
      author: f.author,
      tag: f.tag,
    );
  },
);
