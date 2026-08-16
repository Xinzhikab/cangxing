import 'package:fav_app/features/collections/data/models/category.dart';

abstract class CategoryRepository {
  Future<void> get ready;

  Future<List<Category>> listAll();

  Future<Category?> get(String id);

  Future<Category> create(Category cat);

  Future<Category> update(Category cat);

  Future<void> delete(String id);

  Future<List<Category>> childrenOf(String? parentId);

  Future<void> ensureDefaultCategory();
}
