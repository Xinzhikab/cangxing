import 'dart:async';

import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mailer/mailer.dart' as mail;
import 'package:mailer/smtp_server.dart' as mail;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/settings/data/providers/app_settings_provider.dart';

abstract class ReminderChannel {
  String get key;
  Future<void> schedule(Collection col, DateTime dueAt);
  Future<void> cancel(String collectionId);
}

class SmtpConfig {
  final String host;
  final int port;
  final bool ssl;
  final String username;
  final String password;
  final String recipient;

  const SmtpConfig({
    required this.host,
    required this.port,
    required this.ssl,
    required this.username,
    required this.password,
    required this.recipient,
  });
}

class LocalNotificationReminder implements ReminderChannel {
  final FlutterLocalNotificationsPlugin plugin;
  static final StreamController<String> payloads =
      StreamController<String>.broadcast();

  LocalNotificationReminder(this.plugin);

  @override
  String get key => 'local';

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (resp) {
        if (resp.payload != null) payloads.add(resp.payload!);
      },
    );
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    const channel = AndroidNotificationChannel(
      'review_reminders',
      '回顾提醒',
      description: '想学内容到期提醒',
      importance: Importance.high,
    );
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  @override
  Future<void> schedule(Collection col, DateTime dueAt) async {
    try {
      tz.initializeTimeZones();
    } catch (_) {}
    final now = DateTime.now();
    final scheduled = dueAt.isBefore(now) ? now.add(const Duration(seconds: 5)) : dueAt;
    final id = col.id.hashCode.abs() % 0x7FFFFFFF;

    const androidDetails = AndroidNotificationDetails(
      'review_reminders',
      '回顾提醒',
      priority: Priority.high,
      importance: Importance.max,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    final location = tz.local;
    final scheduledTz = tz.TZDateTime.from(scheduled, location);

    await plugin.zonedSchedule(
      id,
      '📖 到复习时间了',
      col.title,
      scheduledTz,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: col.id,
    );
  }

  @override
  Future<void> cancel(String collectionId) async {
    final id = collectionId.hashCode.abs() % 0x7FFFFFFF;
    await plugin.cancel(id);
  }
}

class SmtpEmailReminder implements ReminderChannel {
  final SmtpConfig smtpConfig;

  SmtpEmailReminder(this.smtpConfig);

  @override
  String get key => 'smtp';

  @override
  Future<void> schedule(Collection col, DateTime dueAt) async {
    return;
  }

  Future<void> sendNow(Collection col) async {
    if (smtpConfig.host.isEmpty || smtpConfig.username.isEmpty) return;
    final dueAt = col.reviewDueAt ?? DateTime.now();
    final message = mail.Message()
      ..from = mail.Address(smtpConfig.username, '收藏 App')
      ..recipients.add(smtpConfig.recipient.isEmpty
          ? smtpConfig.username
          : smtpConfig.recipient)
      ..subject = '复习提醒：${col.title}'
      ..text = '你安排在 ${DateFormat('yyyy-MM-dd HH:mm').format(dueAt)} 复习的收藏到期啦！\n\n'
          '标题：${col.title}\n'
          '作者：${col.author}\n'
          '平台：${col.sourcePlatform}\n'
          '原帖：${col.sourceUrl}\n\n'
          '—— 收藏 App 自动发送';
    final smtpServer = mail.SmtpServer(
      smtpConfig.host,
      port: smtpConfig.port,
      ssl: smtpConfig.ssl,
      username: smtpConfig.username,
      password: smtpConfig.password,
      allowInsecure: !smtpConfig.ssl,
    );
    await mail.send(message, smtpServer).timeout(const Duration(seconds: 20));
  }

  @override
  Future<void> cancel(String id) async {}
}

class CalendarReminder implements ReminderChannel {
  @override
  String get key => 'calendar';

  @override
  Future<void> schedule(Collection col, DateTime dueAt) async {
    final event = Event(
      title: '📖 复习：${col.title}',
      description: '作者：${col.author}\n'
          '平台：${col.sourcePlatform}\n'
          '收藏 ID：${col.id}\n'
          '原帖：${col.sourceUrl}',
      location: '收藏 App',
      startDate: dueAt,
      endDate: dueAt.add(const Duration(hours: 1)),
      allDay: false,
      iosParams: const IOSParams(reminder: Duration(minutes: 0)),
      androidParams: const AndroidParams(emailInvites: []),
    );
    await Add2Calendar.addEvent2Cal(event);
  }

  @override
  Future<void> cancel(String id) async {}
}

class ReminderScheduler {
  final AppSettings settings;
  final FlutterLocalNotificationsPlugin notifications;
  late final Map<String, ReminderChannel> _channels;

  ReminderScheduler(this.settings, this.notifications) {
    _channels = {
      'local': LocalNotificationReminder(notifications)..init(),
      'smtp': SmtpEmailReminder(SmtpConfig(
        host: settings.smtpHost,
        port: settings.smtpPort,
        ssl: settings.smtpSsl,
        username: settings.smtpUsername,
        password: settings.smtpPassword,
        recipient:
            settings.smtpRecipient.isEmpty ? settings.smtpUsername : settings.smtpRecipient,
      )),
      'calendar': CalendarReminder(),
    };
  }

  Future<void> schedule(Collection col, DateTime dueAt) async {
    for (final k in settings.reminderChannels) {
      await _channels[k]?.schedule(col, dueAt);
    }
  }

  Future<void> cancel(String id) async {
    for (final c in _channels.values) {
      await c.cancel(id);
    }
  }

  Future<void> notifyDueNow(Collection col) async {
    final smtp = _channels['smtp'];
    if (smtp is SmtpEmailReminder && settings.reminderChannels.contains('smtp')) {
      try {
        await smtp.sendNow(col);
      } catch (_) {}
    }
  }
}

final notificationPayloadProvider = Provider<Stream<String>>((ref) {
  return LocalNotificationReminder.payloads.stream;
});
