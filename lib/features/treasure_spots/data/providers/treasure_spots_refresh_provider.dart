import 'package:flutter_riverpod/flutter_riverpod.dart';

final treasureSpotsRefreshProvider = StateProvider<int>((ref) => 0);

extension TreasureSpotsRefreshBump on StateController<int> {
  void bump() => state++;
}
