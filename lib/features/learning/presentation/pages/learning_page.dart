import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/collections/data/providers/collections_list_controller.dart';
import 'package:fav_app/features/collections/data/providers/collection_repository_provider.dart';
import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/features/settings/data/providers/app_settings_provider.dart';
import 'package:fav_app/features/learning/data/providers/learning_queue_provider.dart';
import 'package:fav_app/features/learning/data/services/reminder_scheduler.dart';

class LearningPage extends ConsumerStatefulWidget {
  const LearningPage({super.key});

  @override
  ConsumerState<LearningPage> createState() => _LearningPageState();
}

class _LearningPageState extends ConsumerState<LearningPage> {
  final TextEditingController _customDaysCtrl = TextEditingController();
  final ScrollController _pageCtrl = ScrollController();
  int? _pickedCustomDays;

  @override
  void dispose() {
    _customDaysCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  String _platformLabel(String? platform) =>
      CollectionEnums.platformLabel(CollectionEnums.platformFromSql(platform));

  String _statusLabel(String? status) =>
      CollectionEnums.statusLabel(CollectionEnums.statusFromSql(status));

  Future<int?> _pickReviewInterval(BuildContext ctx) async {
    _customDaysCtrl.clear();
    _pickedCustomDays = null;
    return showDialog<int>(
      context: ctx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => SimpleDialog(
          title: const Text('再学一次，几天后复习？'),
          children: [
            ...[1, 3, 7, 14, 30].map((d) => RadioListTile<int>(
              value: d,
              groupValue: _pickedCustomDays,
              onChanged: (v) => setDlgState(() => _pickedCustomDays = v),
              title: Text('$d 天后'),
            )),
            RadioListTile<int>(
              value: -1,
              groupValue: _pickedCustomDays,
              onChanged: (v) => setDlgState(() => _pickedCustomDays = v),
              title: TextField(
                controller: _customDaysCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '自定义天数'),
                onChanged: (_) => setDlgState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton.icon(
                icon: const Icon(Icons.event),
                label: const Text('选具体日期'),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) {
                    final now = DateTime.now();
                    final diff = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
                    if (mounted) Navigator.pop(ctx, diff < 0 ? 0 : diff);
                  }
                },
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                int? result;
                if (_pickedCustomDays == null) {
                  result = null;
                } else if (_pickedCustomDays == -1) {
                  result = int.tryParse(_customDaysCtrl.text.trim());
                } else {
                  result = _pickedCustomDays;
                }
                Navigator.pop(ctx, result);
              },
              child: const Align(
                alignment: Alignment.centerRight,
                child: Text('确定', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markDone(Collection c, LearningGroup g, List<Collection> list, int index) async {
    final repo = ref.read(collectionRepositoryProvider);
    await repo.update(c.copyWith(
      status: CollectionEnums.statusToSql(CollectionStatus.done)!,
      reviewDueAt: null,
    ));
    HapticFeedback.lightImpact();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已完成 ✓'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 800),
        ),
      );
    }
    if ((g == LearningGroup.overdue || g == LearningGroup.today) &&
        index < list.length - 1) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_pageCtrl.hasClients) {
        await _pageCtrl.animateTo(
          _pageCtrl.offset + 72,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
    ref.invalidate(learningQueueProvider);
    ref.invalidate(collectionsListProvider);
  }

  Future<void> _markAllDone(List<Collection> list) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在标记 ${list.length} 项为已完成…'),
        duration: const Duration(seconds: 1),
      ),
    );
    final repo = ref.read(collectionRepositoryProvider);
    await Future.wait(list.map((c) => repo.update(c.copyWith(
          status: CollectionEnums.statusToSql(CollectionStatus.done)!,
          reviewDueAt: null,
        ))));
    ref.invalidate(learningQueueProvider);
    ref.invalidate(collectionsListProvider);
  }

  @override
  Widget build(BuildContext context) {
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
                controller: _pageCtrl,
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$title (${list.length})',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (g == LearningGroup.overdue || g == LearningGroup.today)
            TextButton.icon(
              icon: const Icon(Icons.done_all_outlined, size: 16),
              label: const Text('全部完成'),
              onPressed: () => _markAllDone(list),
            ),
        ],
      ),
    );
    for (var i = 0; i < list.length; i++) {
      final c = list[i];
      final scheme = Theme.of(context).colorScheme;
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.check_circle_outline, color: scheme.primary),
                tooltip: '已完成',
                onPressed: () => _markDone(c, g, list, i),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.menu_book_outlined),
                tooltip: '翻看',
                onPressed: () => context.push('/read/${c.id}?fromLearning=true'),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.repeat_outlined),
                tooltip: '再学一次',
                onPressed: () async {
                  final repo = ref.read(collectionRepositoryProvider);
                  final days = await _pickReviewInterval(context);
                  if (days == null) return;
                  final newDue = DateTime.now().add(Duration(days: days));
                  final updated = c.copyWith(
                      status: CollectionEnums.statusToSql(CollectionStatus.learning)!,
                      reviewDueAt: newDue);
                  await repo.update(updated);
                  final settings = ref.read(appSettingsProvider).valueOrNull;
                  if (settings != null) {
                    final scheduler = await ReminderScheduler.fromSettings(settings);
                    await scheduler.cancel(c.id);
                    await scheduler.schedule(updated, newDue);
                  }
                  ref.invalidate(learningQueueProvider);
                  ref.invalidate(collectionsListProvider);
                },
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'open', child: Text('查看原链接')),
                ],
                onSelected: (v) async {
                  if (v == 'open' && c.sourceUrl.isNotEmpty) {
                    await launchUrl(
                      Uri.parse(c.sourceUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
              ),
            ],
          ),
          onTap: () => context.push('/read/${c.id}'),
        ),
      );
    }
  }
}
