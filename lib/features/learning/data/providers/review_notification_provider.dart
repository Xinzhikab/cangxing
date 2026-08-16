import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fav_app/features/learning/data/services/reminder_scheduler.dart'
    show reminderSchedulerProvider;

export 'package:fav_app/features/learning/data/services/reminder_scheduler.dart'
    show reminderSchedulerProvider, notificationPayloadProvider;

final reviewNotificationServiceProvider = Provider<Object>((ref) {
  return ref.watch(reminderSchedulerProvider);
});

final pendingNotificationLaunchProvider = StateProvider<String?>((ref) => null);
