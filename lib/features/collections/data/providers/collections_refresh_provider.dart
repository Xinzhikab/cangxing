import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 写入操作触发的全局刷新 token。
/// Repository 写入成功后自增，UI Provider watch 此 token 即可自动刷新。
/// 使用方法：
///   UI:  ref.watch(collectionsRefreshProvider);  // 依赖，变更时重建
///   写入: ref.read(collectionsRefreshProvider.notifier).bump();
final collectionsRefreshProvider = StateProvider<int>((ref) => 0);

extension RefreshBump on StateController<int> {
  void bump() => state++;
}
