import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/collections/data/models/collection_note.dart';

abstract class CollectionRepository {
  Future<List<Collection>> list({
    List<String>? categoryPath,
    String? platform,
    String? author,
    String? status,
    String? tag,
    String? sortBy,
    bool descending = true,
  });

  Future<Collection?> get(String id);

  Future<Collection> create(Collection col, {required String contentMd});

  Future<Collection> update(Collection col);

  Future<void> delete(String id);

  Future<List<Collection>> search(String keyword, {int limit = 50});

  Future<List<Map<String, int>>> groupByPlatform();

  Future<List<Map<String, int>>> groupByAuthor();

  Future<List<Map<String, int>>> groupByStatus();

  /// 评论区模式：按时间倒序返回某篇文章的全部笔记
  Future<List<CollectionNote>> listNotes(String collectionId);

  Future<CollectionNote> addNote(CollectionNote note);

  Future<void> deleteNote(String id);

  /// 标签注册表：手动创建的标签名列表（按名称排序）。
  Future<List<String>> listTags();

  /// 注册一个新标签名（已存在则忽略）。
  Future<void> addTag(String name);

  /// 删除标签：从注册表移除，并从所有收藏中剥离该标签。
  Future<void> deleteTag(String name);

  /// 重命名标签：更新注册表，并同步所有收藏中的该标签。
  Future<void> renameTag(String oldName, String newName);
}
