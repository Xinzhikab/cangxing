import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fav_app/features/save/data/services/share_input_service.dart';

final shareInputServiceProvider = Provider<ShareInputService>((ref) {
  final s = ShareInputService();
  s.init();
  return s;
});

final pendingShareExtraProvider = StateProvider<Object?>((ref) => null);

final shareSubscriptionProvider = Provider<StreamSubscription<Object?>>((ref) {
  final svc = ref.read(shareInputServiceProvider);
  return svc.shareEvents.listen((event) {
    ref.read(pendingShareExtraProvider.notifier).state = event;
  });
});
