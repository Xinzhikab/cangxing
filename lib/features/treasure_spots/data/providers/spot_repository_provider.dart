import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fav_app/features/collections/data/services/database_service.dart';
import 'package:fav_app/features/treasure_spots/data/models/treasure_spot.dart';
import 'package:fav_app/features/treasure_spots/data/providers/treasure_spots_refresh_provider.dart';
import 'package:fav_app/features/treasure_spots/data/repositories/spot_repository.dart';
import 'package:fav_app/features/treasure_spots/data/repositories/spot_repository_impl.dart';

class TreasureSpotsFilter {
  final String? folderId;
  final String keyword;
  const TreasureSpotsFilter({this.folderId, this.keyword = ''});

  TreasureSpotsFilter copyWith({Object? folderId = _sentinel, String? keyword, bool clearFolderId = false}) {
    return TreasureSpotsFilter(
      folderId: clearFolderId ? null : (identical(folderId, _sentinel) ? this.folderId : folderId as String?),
      keyword: keyword ?? this.keyword,
    );
  }
}

const Object _sentinel = Object();

final spotRepositoryProvider = Provider<TreasureSpotRepository>((ref) {
  return TreasureSpotRepositoryImpl(db: DatabaseService.instance, onChanged: () => ref.read(treasureSpotsRefreshProvider.notifier).bump());
});

final spotListProvider = FutureProvider.family<List<TreasureSpot>, String?>((ref, folderId) async {
  ref.watch(treasureSpotsRefreshProvider);
  final repo = ref.watch(spotRepositoryProvider);
  if (folderId == null) return repo.listAll();
  if (folderId.isEmpty) return repo.listByFolder(null);
  return repo.listByFolder(folderId);
});

final allSpotsProvider = FutureProvider<List<TreasureSpot>>((ref) async {
  ref.watch(treasureSpotsRefreshProvider);
  return ref.watch(spotRepositoryProvider).listAll();
});

final spotDetailProvider = FutureProvider.autoDispose.family<TreasureSpot?, String>((ref, id) async {
  ref.watch(treasureSpotsRefreshProvider);
  return ref.watch(spotRepositoryProvider).getById(id);
});

final spotSearchProvider = FutureProvider.autoDispose.family<List<TreasureSpot>, String>((ref, keyword) async {
  ref.watch(treasureSpotsRefreshProvider);
  if (keyword.trim().isEmpty) return const [];
  return ref.watch(spotRepositoryProvider).searchByName(keyword);
});

final treasureSpotsFilterProvider = StateProvider<TreasureSpotsFilter>((ref) => const TreasureSpotsFilter());

final filteredTreasureSpotsProvider = FutureProvider<List<TreasureSpot>>((ref) async {
  ref.watch(treasureSpotsRefreshProvider);
  final filter = ref.watch(treasureSpotsFilterProvider);
  final repo = ref.watch(spotRepositoryProvider);
  List<TreasureSpot> base;
  if (filter.folderId == null) {
    base = await repo.listAll();
  } else if (filter.folderId!.isEmpty) {
    base = await repo.listByFolder(null);
  } else {
    base = await repo.listByFolder(filter.folderId);
  }
  final kw = filter.keyword.trim().toLowerCase();
  if (kw.isEmpty) return base;
  return base.where((s) {
    return s.name.toLowerCase().contains(kw) ||
        s.address.toLowerCase().contains(kw) ||
        s.tags.join(' ').toLowerCase().contains(kw) ||
        s.note.toLowerCase().contains(kw);
  }).toList();
});

final treasureSpotByIdProvider = FutureProvider.autoDispose.family<TreasureSpot?, String>((ref, id) async {
  ref.watch(treasureSpotsRefreshProvider);
  return ref.watch(spotRepositoryProvider).getById(id);
});

final folderSpotCountProvider = FutureProvider.autoDispose.family<int, String>((ref, folderId) async {
  ref.watch(treasureSpotsRefreshProvider);
  final list = await ref.watch(spotRepositoryProvider).listByFolder(folderId);
  return list.length;
});

class SpotListNotifier extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  TreasureSpotRepository get _repo => ref.read(spotRepositoryProvider);
  void _bump() => ref.read(treasureSpotsRefreshProvider.notifier).bump();

  Future<TreasureSpot> createSpot(TreasureSpot spot) async {
    TreasureSpot? created;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async { created = await _repo.create(spot); });
    _bump();
    if (state.hasError) Error.throwWithStackTrace(state.error!, state.stackTrace!);
    if (created == null) throw StateError('藏宝点创建失败');
    return created!;
  }

  Future<TreasureSpot> updateSpot(TreasureSpot spot) async {
    TreasureSpot? updated;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async { updated = await _repo.update(spot); });
    _bump();
    if (state.hasError) Error.throwWithStackTrace(state.error!, state.stackTrace!);
    if (updated == null) throw StateError('藏宝点更新失败');
    return updated!;
  }

  Future<void> deleteSpot(String id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async { await _repo.delete(id); });
    _bump();
    if (state.hasError) Error.throwWithStackTrace(state.error!, state.stackTrace!);
  }
}

final spotListNotifierProvider = AsyncNotifierProvider<SpotListNotifier, void>(SpotListNotifier.new);
