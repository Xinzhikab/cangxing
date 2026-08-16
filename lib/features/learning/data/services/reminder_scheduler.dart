import 'dart:async';

import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mailer/mailer.dart' as mail;
import 'package:mailer/smtp_server.dart' as mail;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/settings/data/models/app_settings.dart';
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

/// 统一的本地通知渠道（唯一）。
///
/// 原项目存在两套本地通知管理：
///   1) LocalNotificationReminder（ReminderScheduler 内联使用，LearningPage 直接 new）
///   2) ReviewNotificationService（独立 Provider，app.dart 监听 payload）
/// 两者共享相同的 channel id `review_reminders`，各自初始化 FlutterLocalNotificationsPlugin
/// 存在重复初始化 / 双份调度 / 状态不一致风险。
///
/// 现已合并为一个单例：由 reminderSchedulerProvider 创建并复用。
class UnifiedLocalNotificationChannel implements ReminderChannel {
  final FlutterLocalNotificationsPlugin plugin;

  /// 点击通知时携带的 payload（通常是 collectionId）广播流，供 app.dart 监听跳转。
  final StreamController<String> _payloads = StreamController<String>.broadcast();
  Stream<String> get payloadStream => _payloads.stream;

  /// 同时提供 ValueListenable 形式，兼容 review_notification_provider 的旧接口。
  final ValueNotifier<String?> _payloadNotifier = ValueNotifier(null);
  ValueListenable<String?> get payloadNotifier => _payloadNotifier;

  bool _initialized = false;
  bool _tzInitialized = false;

  UnifiedLocalNotificationChannel(this.plugin);

  @override
  String get key => 'local';

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (resp) {
        if (resp.payload == null) return;
        _payloadNotifier.value = resp.payload;
        _payloads.add(resp.payload!);
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

  /// 消费并清空上次 pending 的 payload（应用冷启动由通知拉起时使用）。
  String? consumePendingPayload() {
    final p = _payloadNotifier.value;
    _payloadNotifier.value = null;
    return p;
  }

  void _ensureTz() {
    if (_tzInitialized) return;
    try {
      tz.initializeTimeZones();
      _tzInitialized = true;
    } catch (e, st) {
      debugPrint('[Reminder] tz init: $e\n$st');
    }
  }

  @override
  Future<void> schedule(Collection col, DateTime dueAt) async {
    _ensureTz();
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

  /// 批量重排所有回顾通知（App 启动时用）。
  Future<void> rescheduleAll(
    List<({String id, String title, DateTime? dueAt})> items,
  ) async {
    await plugin.cancelAll();
    // 构造一个最小的「伪 Collection」让 schedule 复用
    for (final it in items) {
      if (it.dueAt == null) continue;
      await schedule(
        Collection(
          id: it.id,
          title: it.title,
          type: '',
          sourcePlatform: '',
          sourceUrl: '',
          author: '',
          collectedAt: DateTime.now(),
          category: const [],
          images: const [],
          tags: const [],
          note: '',
          status: '',
          rawInput: '',
        ),
        it.dueAt!,
      );
    }
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
      ..from = mail.Address(smtpConfig.username, '藏星')
      ..recipients.add(smtpConfig.recipient.isEmpty
          ? smtpConfig.username
          : smtpConfig.recipient)
      ..subject = '复习提醒：${col.title}'
      ..text = '你安排在 ${DateFormat('yyyy-MM-dd HH:mm').format(dueAt)} 复习的收藏到期啦！\n\n'
          '标题：${col.title}\n'
          '作者：${col.author}\n'
          '平台：${col.sourcePlatform}\n'
          '原帖：${col.sourceUrl}\n\n'
          '—— 藏星 · 自动发送';
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
      location: '藏星',
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

/// 统一的回顾提醒调度器。由 reminderSchedulerProvider 创建为单例，
/// 业务层（LearningPage / ReadPage / 设置页变更渠道后）只需 `ref.read` 即可。
class ReminderScheduler {
  final UnifiedLocalNotificationChannel localChannel;
  final SmtpEmailReminder? smtpChannel;
  final CalendarReminder calendarChannel;
  final Set<String> reminderChannels;

  ReminderScheduler._({
    required this.localChannel,
    required this.smtpChannel,
    required this.calendarChannel,
    required this.reminderChannels,
  });

  /// 工厂：按 AppSettings 构造三个渠道，本地通知永远存在。
  static Future<ReminderScheduler> fromSettings(AppSettings settings) async {
    final local = UnifiedLocalNotificationChannel(FlutterLocalNotificationsPlugin());
    await local.init();
    final smtp = (settings.smtpHost.isNotEmpty && settings.smtpUsername.isNotEmpty)
        ? SmtpEmailReminder(SmtpConfig(
            host: settings.smtpHost,
            port: settings.smtpPort,
            ssl: settings.smtpSsl,
            username: settings.smtpUsername,
            password: settings.smtpPassword,
            recipient:
                settings.smtpRecipient.isEmpty ? settings.smtpUsername : settings.smtpRecipient,
          ))
        : null;
    return ReminderScheduler._(
      localChannel: local,
      smtpChannel: smtp,
      calendarChannel: CalendarReminder(),
      reminderChannels: settings.reminderChannels,
    );
  }

  /// 通知点击 payload（ValueListenable 形式，app.dart 监听跳转）。
  ValueListenable<String?> get payloadNotifier => localChannel.payloadNotifier;

  /// 消费 pending 启动 payload。
  String? consumePendingPayload() => localChannel.consumePendingPayload();

  Future<void> schedule(Collection col, DateTime dueAt) async {
    for (final k in reminderChannels) {
      switch (k) {
        case 'local':
          await localChannel.schedule(col, dueAt);
          break;
        case 'smtp':
          // SMTP 不预排（邮件服务商通常限制计划发送），保留接口由 notifyDueNow 触发
          break;
        case 'calendar':
          await calendarChannel.schedule(col, dueAt);
          break;
      }
    }
  }

  Future<void> cancel(String id) async {
    await localChannel.cancel(id);
    // smtpChannel 不预排故无需 cancel
    // calendarChannel 官方插件不支持取消，保留空实现
  }

  Future<void> notifyDueNow(Collection col) async {
    if (smtpChannel != null && reminderChannels.contains('smtp')) {
      try {
        await smtpChannel!.sendNow(col);
      } catch (e, st) {
        debugPrint('[Reminder] smtp send: $e\n$st');
      }
    }
  }

  Future<void> rescheduleAll(
    List<({String id, String title, DateTime? dueAt})> items,
  ) {
    return localChannel.rescheduleAll(items);
  }
}

/// Riverpod 入口：每次 appSettings 变化时重新创建调度器（用户改 SMTP / 渠道开关后立即生效）。
final reminderSchedulerProvider = Provider<Future<ReminderScheduler>>((ref) async {
  final settingsAsync = ref.watch(appSettingsProvider);
  final AppSettings settings = settingsAsync.valueOrNull ??
      await ref.read(appSettingsProvider.future);
  return ReminderScheduler.fromSettings(settings);
});

/// 通知 payload 的 ValueListenable 接口（保持 review_notification_provider 的旧签名，
/// 便于 app.dart 无需大改即可切换）。
final notificationPayloadProvider = Provider<ValueListenable<String?>>((ref) {
  final schedulerFuture = ref.watch(reminderSchedulerProvider);
  // schedulerFuture 完成后 payloadNotifier 才可用；但 initState 处
  // app.dart 已通过 PostFrame 延后读取，此时 Future 已完成。
  // ignore: discarded_futures
  final schedulerFuture2 = schedulerFuture;
  return _FutureValueListenable(schedulerFuture2);
});

/// 把 `Future<ValueListenable>` 封装成一个 ValueListenable。
/// scheduler 初始化完成前 value 恒为 null，完成后透传内部 payloadNotifier。
class _FutureValueListenable implements ValueListenable<String?> {
  _FutureValueListenable(Future<ReminderScheduler> future) {
    future.then((s) {
      _inner = s.payloadNotifier;
      _inner?.addListener(() {
        value = _inner?.value;
        for (final l in List.of(_listeners)) {
          l();
        }
      });
      // 已有的 pending 值立即通知
      if (_inner?.value != null) {
        value = _inner?.value;
        for (final l in List.of(_listeners)) {
          l();
        }
      }
    });
  }

  ValueListenable<String?>? _inner;

  @override
  String? value;

  final _listeners = <VoidCallback>{};

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }
}
