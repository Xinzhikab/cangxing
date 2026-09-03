import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 藏宝点写入操作触发的全局刷新 token。
/// Repository 写入成功后自增，UI Provider watch 此 token 即可自动刷新。
/// 使用方法：
///   UI:  ref.watch(treasureSpotsRefreshProvider);
///   写入: ref.read(treasureSpotsRefreshProvider.notifier).bump();
final treasureSpotsRefreshProvider = StateProvider<int>((ref) => 0);

extension TreasureSpotsRefreshBump on StateController<int> {
  void bump() => state++;
}
