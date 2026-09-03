import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fav_app/features/collections/data/services/database_service.dart';
import 'package:fav_app/features/treasure_spots/data/models/spot_folder.dart';
import 'package:fav_app/features/treasure_spots/data/providers/treasure_spots_refresh_provider.dart';
import 'package:fav_app/features/treasure_spots/data/repositories/spot_folder_repository.dart';
import 'package:fav_app/features/treasure_spots/data/repositories/spot_folder_repository_impl.dart';

// ================= Repository Provider =================

final spotFolderRepositoryProvider = Provider<SpotFolderRepository>((ref) {
  return SpotFolderRepositoryImpl(
    db: DatabaseService.instance,
    onChanged: () => ref.read(treasureSpotsRefreshProvider.notifier).bump(),
  );
});

// ================= Read Providers (FutureProvider) =================

final spotFolderListProvider = FutureProvider<List<SpotFolder>>((ref) async {
  ref.watch(treasureSpotsRefreshProvider);
  final repo = ref.watch(spotFolderRepositoryProvider);
  return repo.listAll();
});

final spotFolderDetailProvider =
    FutureProvider.autoDispose.family<SpotFolder?, String>((ref, id) async {
  ref.watch(treasureSpotsRefreshProvider);
  final repo = ref.watch(spotFolderRepositoryProvider);
  return repo.getById(id);
});

// ================= Mutation Notifier (AsyncNotifierProvider) =================

class SpotFolderListNotifier extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {
    // 就绪状态；列表由 spotFolderListProvider 管理，通过 refresh token 自动刷新
    return;
  }

  SpotFolderRepository get _repo => ref.read(spotFolderRepositoryProvider);
  void _bump() => ref.read(treasureSpotsRefreshProvider.notifier).bump();

  Future<SpotFolder> createFolder({
    required String name,
    IconData? icon,
    Color? color,
    int? sortOrder,
    String? id,
  }) async {
    SpotFolder? created;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final folder = SpotFolder(
        id: id ?? '',
        name: name,
        iconCode: icon?.codePoint ?? Icons.folder.codePoint,
        colorValue: (color ?? Colors.blue).value,
        sortOrder: sortOrder ?? 0,
      );
      created = await _repo.create(folder);
    });
    _bump();
    if (state.hasError) {
      Error.throwWithStackTrace(state.error!, state.stackTrace!);
    }
    if (created == null) {
      throw StateError('文件夹创建失败: 未返回创建后对象');
    }
    return created!;
  }

  Future<SpotFolder> updateFolder(SpotFolder folder) async {
    SpotFolder? updated;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      updated = await _repo.update(folder);
    });
    _bump();
    if (state.hasError) {
      Error.throwWithStackTrace(state.error!, state.stackTrace!);
    }
    if (updated == null) {
      throw StateError('文件夹更新失败: 未返回更新后对象');
    }
    return updated!;
  }

  Future<void> deleteFolder(String id) async {
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

final spotFolderListNotifierProvider =
    AsyncNotifierProvider<SpotFolderListNotifier, void>(
        SpotFolderListNotifier.new);
