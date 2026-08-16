import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/collections/data/providers/collections_list_controller.dart';
import 'package:fav_app/features/collections/data/providers/collection_repository_provider.dart';
import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/features/settings/data/providers/app_settings_provider.dart';
import 'package:fav_app/features/learning/data/providers/learning_queue_provider.dart';
import 'package:fav_app/features/learning/data/services/reminder_scheduler.dart';

class LearningPage extends ConsumerWidget {
  const LearningPage({super.key});

  String _platformLabel(String? platform) {
    switch (platform) {
      case SourcePlatform.douyin:
        return '抖音';
      case SourcePlatform.xiaoheihe:
        return '小黑盒';
      case SourcePlatform.coolapk:
        return '酷安';
      default:
        return '其他';
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case CollectionStatus.learning:
        return '想学';
      case CollectionStatus.done:
        return '完成';
      default:
        return '其他';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('想学'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '回顾节奏与渠道',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Consumer(
        builder: (context, ref, _) {
          final q = ref.watch(learningQueueProvider);
          return q.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, __) => Center(child: Text('$e')),
            data: (map) {
              final order = [
                LearningGroup.overdue,
                LearningGroup.today,
                LearningGroup.within3Days,
                LearningGroup.later
              ];
              final titles = {
                LearningGroup.overdue: '🔴 已到期',
                LearningGroup.today: '🟡 今天到期',
                LearningGroup.within3Days: '🟢 3 天内',
                LearningGroup.later: '⏳ 之后'
              };
              if (map.values.every((l) => l.isEmpty)) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 80,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      const Text('暂无想学内容'),
                      const SizedBox(height: 8),
                      Text(
                        '阅读页点击底部「🧠 想学」安排回顾',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              }
              return ListView(
                children: [
                  for (final g in order)
                    ..._buildSection(
                        g, titles[g]!, map[g]!, ref, context)
                ],
              );
            },
          );
        },
      ),
    );
  }

  Iterable<Widget> _buildSection(LearningGroup g, String title,
      List<Collection> list, WidgetRef ref, BuildContext context) sync* {
    if (list.isEmpty) return;
    yield Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        '$title (${list.length})',
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
    for (final c in list)
      yield Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: ListTile(
          title: Text(
            c.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
              '${_platformLabel(c.sourcePlatform)} · ${c.reviewDueAt == null ? '—' : DateFormat('MM-dd HH:mm').format(c.reviewDueAt!)}'),
          leading: CircleAvatar(child: Text(_statusLabel(c.status)[0])),
          trailing: PopupMenuButton<String>(
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'read', child: Text('去翻看')),
              PopupMenuItem(value: 'again', child: Text('再学一次')),
              PopupMenuItem(value: 'done', child: Text('标已完成')),
            ],
            onSelected: (v) async {
              final repo = ref.read(collectionRepositoryProvider);
              if (v == 'read') {
                context.push('/read/${c.id}');
                return;
              }
              if (v == 'done') {
                await repo.update(c.copyWith(
                    status: CollectionStatus.done, reviewDueAt: null));
              }
              if (v == 'again') {
                final days = await showDialog<int>(
                  context: context,
                  builder: (ctx) => SimpleDialog(
                    title: const Text('再学一次，几天后复习？'),
                    children: [1, 3, 7, 14, 30]
                        .map((d) => SimpleDialogOption(
                              onPressed: () => Navigator.pop(ctx, d),
                              child: Text('$d 天后'),
                            ))
                        .toList(),
                  ),
                );
                if (days == null) return;
                final newDue = DateTime.now().add(Duration(days: days));
                final updated = c.copyWith(
                    status: CollectionStatus.learning, reviewDueAt: newDue);
                await repo.update(updated);
                final settings = ref.read(appSettingsProvider).valueOrNull;
                if (settings != null) {
                  final scheduler = ReminderScheduler(
                      settings, FlutterLocalNotificationsPlugin());
                  await scheduler.cancel(c.id);
                  await scheduler.schedule(updated, newDue);
                }
              }
              ref.invalidate(learningQueueProvider);
              ref.invalidate(collectionsListProvider);
            },
          ),
          onTap: () => context.push('/read/${c.id}'),
        ),
      );
  }
}
