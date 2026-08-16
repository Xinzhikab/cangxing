import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fav_app/features/collections/data/models/category.dart';
import 'package:fav_app/features/collections/data/providers/category_repository_provider.dart';

class CategoryNode {
  final Category category;
  final List<CategoryNode> children;

  CategoryNode({
    required this.category,
    this.children = const [],
  });

  int get totalDescendantCount =>
      children.fold(0, (sum, c) => sum + 1 + c.totalDescendantCount);
}

final categoryListProvider = FutureProvider<List<Category>>((ref) async {
  final repo = ref.watch(categoryRepositoryProvider);
  await repo.ready;
  return repo.listAll();
});

List<({Category cat, int level})> buildTreeView(
  List<Category> all, {
  String? parentId,
  int level = 0,
}) {
  final siblings =
      all.where((c) => c.parentId == parentId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final result = <({Category cat, int level})>[];
  for (final s in siblings) {
    result.add((cat: s, level: level));
    result.addAll(buildTreeView(all, parentId: s.id, level: level + 1));
  }
  return result;
}

final categoriesListProvider = FutureProvider<List<Category>>((ref) async {
  final repo = ref.watch(categoryRepositoryProvider);
  await repo.ready;
  return repo.listAll();
});

final categoryTreeProvider = Provider<AsyncValue<List<CategoryNode>>>((ref) {
  return ref.watch(categoriesListProvider).whenData((list) {
    final byParent = <String?, List<Category>>{};
    for (final c in list) {
      byParent.putIfAbsent(c.parentId, () => []).add(c);
    }
    byParent.values
        .forEach((l) => l.sort((a, b) => a.sortOrder.compareTo(b.sortOrder)));

    List<CategoryNode> buildNodes(String? parentId) {
      final items = byParent[parentId] ?? [];
      return items
          .map((c) => CategoryNode(category: c, children: buildNodes(c.id)))
          .toList();
    }

    return buildNodes(null);
  });
});

final selectedCategoryPathProvider =
    StateProvider<List<String>>((ref) => []);
