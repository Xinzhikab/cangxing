import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fav_app/features/learning/data/services/review_notification_service.dart';

final reviewNotificationServiceProvider =
    Provider<ReviewNotificationService>((ref) {
  final svc = ReviewNotificationService();
  svc.init();
  return svc;
});

final pendingNotificationLaunchProvider = StateProvider<String?>((ref) => null);

final notificationPayloadProvider = Provider<ValueListenable<String?>>((ref) {
  return ref.watch(reviewNotificationServiceProvider).payloadNotifier;
});
