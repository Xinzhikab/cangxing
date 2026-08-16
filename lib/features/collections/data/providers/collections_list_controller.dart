import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/collections/data/providers/collections_refresh_provider.dart';
import 'package:fav_app/features/collections/data/providers/collection_repository_provider.dart';
import 'package:fav_app/features/collections/data/repositories/collection_repository.dart';

class CollectionsFilter {
  final String keyword;
  final List<String>? categoryPath;
  final SourcePlatform? platform;
  final String? author;
  final CollectionStatus? status;
  final CollectionSortField sortBy;
  final bool descending;
  final bool pinnedOnly;

  const CollectionsFilter({
    this.keyword = '',
    this.categoryPath,
    this.platform,
    this.author,
    this.status,
    this.sortBy = CollectionSortField.collectedAt,
    this.descending = true,
    this.pinnedOnly = false,
  });

  CollectionsFilter copyWith({
    String? keyword,
    List<String>? categoryPath,
    SourcePlatform? platform,
    String? author,
    CollectionStatus? status,
    CollectionSortField? sortBy,
    bool? descending,
    bool? pinnedOnly,
  }) {
    return CollectionsFilter(
      keyword: keyword ?? this.keyword,
      categoryPath: categoryPath ?? this.categoryPath,
      platform: platform ?? this.platform,
      author: author ?? this.author,
      status: status ?? this.status,
      sortBy: sortBy ?? this.sortBy,
      descending: descending ?? this.descending,
      pinnedOnly: pinnedOnly ?? this.pinnedOnly,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! CollectionsFilter) return false;
    if (other.keyword != keyword) return false;
    if (other.platform != platform) return false;
    if (other.author != author) return false;
    if (other.status != status) return false;
    if (other.sortBy != sortBy) return false;
    if (other.descending != descending) return false;
    if (other.pinnedOnly != pinnedOnly) return false;
    if (other.categoryPath?.length != categoryPath?.length) return false;
    if (categoryPath != null && other.categoryPath != null) {
      for (var i = 0; i < categoryPath!.length; i++) {
        if (other.categoryPath![i] != categoryPath![i]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        keyword,
        platform,
        author,
        status,
        sortBy,
        descending,
        pinnedOnly,
        categoryPath == null ? null : Object.hashAll(categoryPath!),
      );
}

class CollectionsListController extends StateNotifier<AsyncValue<List<Collection>>> {
  final CollectionRepository repo;
  CollectionsFilter _filter;

  CollectionsListController(this.repo, CollectionsFilter initialFilter)
      : _filter = initialFilter,
        super(const AsyncValue.loading()) {
    refresh();
  }

  void setFilter(CollectionsFilter newFilter) {
    if (newFilter == _filter) return;
    _filter = newFilter;
    state = const AsyncValue.loading();
    refresh();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      if (_filter.keyword.trim().isNotEmpty) return repo.search(_filter.keyword);
      return repo.list(
        categoryPath: _filter.categoryPath,
        platform: _filter.platform,
        author: _filter.author,
        status: _filter.status,
        sortBy: _filter.sortBy,
        descending: _filter.descending,
        pinnedOnly: _filter.pinnedOnly,
      );
    });
  }
}

final collectionsFilterProvider =
    StateProvider<CollectionsFilter>((ref) => const CollectionsFilter(
          keyword: '',
          sortBy: CollectionSortField.collectedAt,
          descending: true,
        ));

final collectionsListProvider =
    StateNotifierProvider<CollectionsListController, AsyncValue<List<Collection>>>((ref) {
  ref.watch(collectionsRefreshProvider);
  return CollectionsListController(
    ref.watch(collectionRepositoryProvider),
    ref.read(collectionsFilterProvider),
  );
});

final groupStatsProvider =
    FutureProvider<Map<String, List<Map<String, int>>>>((ref) async {
  ref.watch(collectionsRefreshProvider);
  final repo = ref.watch(collectionRepositoryProvider);
  return {
    'platforms': await repo.groupByPlatform(),
    'authors': await repo.groupByAuthor(),
    'statuses': await repo.groupByStatus(),
  };
});

final allTagsProvider = FutureProvider<Map<String, int>>((ref) async {
  ref.watch(collectionsRefreshProvider);
  final repo = ref.watch(collectionRepositoryProvider);
  final cols = await repo.listMetaOnly();
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

class CategoryArticlesFilter {
  final List<String> categoryPath;
  final SourcePlatform? platform;
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

final categoryArticlesProvider = FutureProvider.family<
    List<Collection>,
    CategoryArticlesFilter>(
  (ref, f) async {
    ref.watch(collectionsRefreshProvider);
    final repo = ref.watch(collectionRepositoryProvider);
    return repo.list(
      categoryPath: f.categoryPath,
      platform: f.platform,
      author: f.author,
      tag: f.tag,
    );
  },
);

class _SearchHistoryNotifier extends Notifier<List<String>> {
  static const _key = 'search_history_v1';
  static const _max = 5;

  @override
  List<String> build() {
    _loadAsync();
    return const <String>[];
  }

  Future<void> _loadAsync() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_key);
    if (stored != null && stored.isNotEmpty) {
      state = stored;
    }
  }

  void add(String kw) {
    if (kw.trim().isEmpty) return;
    final trimmed = kw.trim();
    final list = [
      trimmed,
      ...state.where((e) => e != trimmed).take(_max - 1),
    ].toList();
    state = list;
    SharedPreferences.getInstance().then((p) => p.setStringList(_key, list));
  }

  void clear() {
    state = const <String>[];
    SharedPreferences.getInstance().then((p) => p.remove(_key));
  }

  void removeAt(int i) {
    if (i < 0 || i >= state.length) return;
    final list = List<String>.from(state)..removeAt(i);
    state = list;
    SharedPreferences.getInstance().then((p) => p.setStringList(_key, list));
  }
}

final searchHistoryProvider =
    NotifierProvider<_SearchHistoryNotifier, List<String>>(
  _SearchHistoryNotifier.new,
);
