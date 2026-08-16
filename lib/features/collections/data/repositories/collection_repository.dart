import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/collections/data/models/collection_note.dart';

abstract class CollectionRepository {
  Future<List<Collection>> list({
    List<String>? categoryPath,
    SourcePlatform? platform,
    String? author,
    CollectionStatus? status,
    String? tag,
    CollectionSortField sortBy = CollectionSortField.collectedAt,
    bool descending = true,
    bool pinnedOnly = false,
  });

  Future<List<Collection>> listMetaOnly({
    List<String>? categoryPath,
    SourcePlatform? platform,
    String? author,
    CollectionStatus? status,
    String? tag,
    CollectionSortField sortBy = CollectionSortField.collectedAt,
    bool descending = true,
    bool pinnedOnly = false,
  });

  Future<Collection?> get(String id);

  Future<Collection> create(Collection col, {required String contentMd});

  Future<Collection> update(Collection col);

  Future<void> delete(String id);

  /// 回收站：列出所有已软删除的收藏（按删除时间倒序，仅 meta）。
  Future<List<Collection>> listTrashed();

  /// 回收站：恢复一条软删除的收藏（清除 deleted_at，重建 FTS 索引）。
  Future<void> restore(String id);

  /// 回收站：彻底删除——删 DB 行 + FTS + meta/content/images 文件。
  Future<void> permanentDelete(String id);

  /// 回收站：清空回收站（对所有已删除项执行 permanentDelete）。
  Future<void> emptyTrash();

  /// 置顶切换：已置顶 → 取消置顶；未置顶 → 置顶（置顶时间=now）。
  Future<void> togglePin(String id);

  /// 批量置顶 / 取消置顶（pinned=true 全置顶，pinned=false 全不置顶）。
  Future<void> setPinnedBatch(List<String> ids, {required bool pinned});

  Future<List<Collection>> search(String keyword, {int limit = 50});

  Future<List<Map<String, int>>> groupByPlatform();

  Future<List<Map<String, int>>> groupByAuthor();

  Future<List<Map<String, int>>> groupByStatus();

  Future<List<CollectionNote>> listNotes(String collectionId);

  Future<CollectionNote> addNote(CollectionNote note);

  Future<void> deleteNote(String id);

  Future<List<String>> listTags();

  @Deprecated('tags 注册表已废弃，此方法 no-op')
  Future<void> addTag(String name);

  @Deprecated('tags 注册表已废弃，仅同步 collections.tags_json 列')
  Future<void> deleteTag(String name);

  @Deprecated('tags 注册表已废弃，仅同步 collections.tags_json 列')
  Future<void> renameTag(String oldName, String newName);
}
