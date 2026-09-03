import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fav_app/features/collections/data/services/database_service.dart';
import 'package:fav_app/features/treasure_spots/data/models/treasure_spot.dart';
import 'package:fav_app/features/treasure_spots/data/providers/treasure_spots_refresh_provider.dart';
import 'package:fav_app/features/treasure_spots/data/repositories/spot_repository.dart';
import 'package:fav_app/features/treasure_spots/data/repositories/spot_repository_impl.dart';

// ================= 筛选条件模型（兼容 UI 的 copyWith 调用）=================

/// 藏宝点筛选条件：文件夹 + 关键词
class TreasureSpotsFilter {
  final String? folderId; // null = 全部文件夹；'' = 未归类；其他 = 某文件夹 id
  final String keyword;

  const TreasureSpotsFilter({
    this.folderId,
    this.keyword = '',
  });

  TreasureSpotsFilter copyWith({
    Object? folderId = _sentinel,
    String? keyword,
    bool clearFolderId = false,
  }) {
    return TreasureSpotsFilter(
      folderId: clearFolderId
          ? null
          : (identical(folderId, _sentinel)
              ? this.folderId
              : folderId as String?),
      keyword: keyword ?? this.keyword,
    );
  }
}

/// 哨兵对象，用于区分「未传 folderId」与「显式传 null」
const Object _sentinel = Object();

// ================= Repository Provider =================

final spotRepositoryProvider = Provider<TreasureSpotRepository>((ref) {
  return TreasureSpotRepositoryImpl(
    db: DatabaseService.instance,
    onChanged: () => ref.read(treasureSpotsRefreshProvider.notifier).bump(),
  );
});

// ================= Read Providers (FutureProvider) =================

/// 按文件夹列出藏宝点。
/// - folderId == null → 列出全部藏宝点（全部）
/// - folderId == ''   → 列出未归类的藏宝点（folder_id IS NULL）
/// - folderId 为其他值 → 列出该文件夹下的藏宝点
final spotListProvider =
    FutureProvider.family<List<TreasureSpot>, String?>((ref, folderId) async {
  ref.watch(treasureSpotsRefreshProvider);
  final repo = ref.watch(spotRepositoryProvider);
  if (folderId == null) return repo.listAll();
  if (folderId.isEmpty) return repo.listByFolder(null);
  return repo.listByFolder(folderId);
});

/// 列出所有藏宝点（不分文件夹）。
final allSpotsProvider = FutureProvider<List<TreasureSpot>>((ref) async {
  ref.watch(treasureSpotsRefreshProvider);
  final repo = ref.watch(spotRepositoryProvider);
  return repo.listAll();
});

final spotDetailProvider =
    FutureProvider.autoDispose.family<TreasureSpot?, String>((ref, id) async {
  ref.watch(treasureSpotsRefreshProvider);
  final repo = ref.watch(spotRepositoryProvider);
  return repo.getById(id);
});

final spotSearchProvider =
    FutureProvider.autoDispose.family<List<TreasureSpot>, String>((ref, keyword) async {
  ref.watch(treasureSpotsRefreshProvider);
  if (keyword.trim().isEmpty) return const [];
  final repo = ref.watch(spotRepositoryProvider);
  return repo.searchByName(keyword);
});

// ================= UI 依赖的筛选与辅助 Provider =================

/// 筛选条件（文件夹 id + 搜索关键词）。UI 通过 notifier 修改 state。
final treasureSpotsFilterProvider =
    StateProvider<TreasureSpotsFilter>((ref) => const TreasureSpotsFilter());

/// 过滤后的藏宝点列表（FutureProvider，直接给 UI 列表 watch）。
/// 组合 treasureSpotsFilterProvider 与 spotRepositoryProvider：
///   - keyword 空 且 folderId 空 → listAll
///   - folderId 不为空 → 先按 folderId 查（注意 null='' 的含义）
///   - 关键词非空时，再在 Dart 层做 name/address/tags/note 的模糊匹配
final filteredTreasureSpotsProvider =
    FutureProvider<List<TreasureSpot>>((ref) async {
  ref.watch(treasureSpotsRefreshProvider);
  final filter = ref.watch(treasureSpotsFilterProvider);
  final repo = ref.watch(spotRepositoryProvider);

  // 1) 按 folderId 取基础列表
  List<TreasureSpot> base;
  if (filter.folderId == null) {
    base = await repo.listAll();
  } else if (filter.folderId!.isEmpty) {
    // '' 表示 folder_id IS NULL（未归类）
    base = await repo.listByFolder(null);
  } else {
    base = await repo.listByFolder(filter.folderId);
  }

  // 2) 关键词再做 Dart 层模糊过滤（name/address/tags.join/note）
  final kw = filter.keyword.trim().toLowerCase();
  if (kw.isEmpty) return base;
  return base.where((s) {
    return s.name.toLowerCase().contains(kw) ||
        s.address.toLowerCase().contains(kw) ||
        s.tags.join(' ').toLowerCase().contains(kw) ||
        s.note.toLowerCase().contains(kw);
  }).toList();
});

/// 按 id 获取单个藏宝点（UI 任务要求的名字）。
/// 与 spotDetailProvider 语义相同，同时提供两个名字保证调用方都可编译。
final treasureSpotByIdProvider =
    FutureProvider.autoDispose.family<TreasureSpot?, String>((ref, id) async {
  ref.watch(treasureSpotsRefreshProvider);
  final repo = ref.watch(spotRepositoryProvider);
  return repo.getById(id);
});

/// 指定文件夹下的藏宝点数量（用于文件夹管理页 Tile 右侧数字）。
final folderSpotCountProvider =
    FutureProvider.autoDispose.family<int, String>((ref, folderId) async {
  ref.watch(treasureSpotsRefreshProvider);
  final repo = ref.watch(spotRepositoryProvider);
  final list = await repo.listByFolder(folderId);
  return list.length;
});

// ================= Mutation Notifier (AsyncNotifierProvider) =================

class SpotListNotifier extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {
    // 就绪状态；不持有列表（列表状态由 spotListProvider 管理，通过 refresh token 自动刷新）
    return;
  }

  TreasureSpotRepository get _repo => ref.read(spotRepositoryProvider);
  void _bump() => ref.read(treasureSpotsRefreshProvider.notifier).bump();

  Future<TreasureSpot> createSpot(TreasureSpot spot) async {
    TreasureSpot? created;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      created = await _repo.create(spot);
    });
    _bump();
    if (state.hasError) {
      Error.throwWithStackTrace(state.error!, state.stackTrace!);
    }
    if (created == null) {
      throw StateError('藏宝点创建失败: 未返回创建后对象');
    }
    return created!;
  }

  Future<TreasureSpot> updateSpot(TreasureSpot spot) async {
    TreasureSpot? updated;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      updated = await _repo.update(spot);
    });
    _bump();
    if (state.hasError) {
      Error.throwWithStackTrace(state.error!, state.stackTrace!);
    }
    if (updated == null) {
      throw StateError('藏宝点更新失败: 未返回更新后对象');
    }
    return updated!;
  }

  Future<void> deleteSpot(String id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repo.delete(id);
    });
    _bump();
    if (state.hasError) {
      Error.throwWithStackTrace(state.error!, state.stackTrace!);
    }
  }
}

final spotListNotifierProvider =
    AsyncNotifierProvider<SpotListNotifier, void>(SpotListNotifier.new);
