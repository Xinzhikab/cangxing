import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class ReviewNotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  final ValueNotifier<String?> _pendingLaunchPayload = ValueNotifier(null);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (NotificationResponse resp) {
        _pendingLaunchPayload.value = resp.payload;
      },
    );

    const channel = AndroidNotificationChannel(
      'review_reminders',
      '回顾提醒',
      description: '想学内容到期提醒',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  ValueListenable<String?> get payloadNotifier => _pendingLaunchPayload;

  String? consumePendingPayload() {
    final p = _pendingLaunchPayload.value;
    _pendingLaunchPayload.value = null;
    return p;
  }

  Future<void> schedule(
      String collectionId, String title, DateTime dueAt) async {
    final now = DateTime.now();
    final scheduled =
        dueAt.isBefore(now) ? now.add(const Duration(seconds: 5)) : dueAt;
    final id = collectionId.hashCode.abs() % 0x7FFFFFFF;

    const androidDetails = AndroidNotificationDetails(
      'review_reminders',
      '回顾提醒',
      priority: Priority.high,
      importance: Importance.max,
    );
    const iosDetails = DarwinNotificationDetails();
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    final location = tz.local;
    final scheduledTz = tz.TZDateTime.from(scheduled, location);

    await _plugin.zonedSchedule(
      id,
      '该回顾啦：${title.length > 20 ? '${title.substring(0, 20)}…' : title}',
      '点击进入阅读并标记已完成',
      scheduledTz,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: collectionId,
    );
  }

  Future<void> cancel(String collectionId) async {
    final id = collectionId.hashCode.abs() % 0x7FFFFFFF;
    await _plugin.cancel(id);
  }

  Future<void> rescheduleAll(
      List<({String id, String title, DateTime? dueAt})> items) async {
    await _plugin.cancelAll();
    for (final it in items) {
      if (it.dueAt != null) {
        await schedule(it.id, it.title, it.dueAt!);
      }
    }
  }
}

void initializeTimeZones() {
  tz.initializeTimeZones();
}
