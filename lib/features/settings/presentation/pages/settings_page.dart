import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/core/utils/app_logger.dart';
import 'package:fav_app/features/settings/data/models/app_settings.dart';
import 'package:fav_app/features/settings/data/providers/app_settings_provider.dart';
import 'package:fav_app/features/settings/data/providers/backup_service_provider.dart';
import 'package:fav_app/features/settings/data/providers/storage_stats_provider.dart';
import 'package:fav_app/features/settings/data/services/backup_service.dart';
import 'package:fav_app/features/settings/data/services/maintenance_service.dart';

const _reviewIntervalOptions = [1, 3, 7, 15, 30];

/// 阅读软件（legado 风格）设置页：小节标题 + 圆角卡片分组 + 色调图标。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  void _toggleChannel(WidgetRef ref, AppSettings s, String ch, bool enable) {
    final set = Set<String>.from(s.reminderChannels);
    enable ? set.add(ch) : set.remove(ch);
    ref
        .read(appSettingsProvider.notifier)
        .updateSettings(reminderChannels: set);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sAsync = ref.watch(appSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: sAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (s) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Material(
                  color: scheme.primaryContainer.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.push('/settings/about'),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(Icons.auto_stories_rounded,
                              size: 40, color: scheme.primary),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('藏星',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text('本地优先 · 收藏与间隔复习',
                                    style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              color: scheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _SettingsSection(
                title: '主题与外观',
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.dark_mode_outlined,
                                  size: 20, color: scheme.onPrimaryContainer),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '主题模式',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '选择浅色、深色或跟随系统',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<ThemeModeValue>(
                            segments: const [
                              ButtonSegment(
                                value: ThemeModeValue.system,
                                label: Text('跟随'),
                                icon: Icon(Icons.auto_awesome),
                              ),
                              ButtonSegment(
                                value: ThemeModeValue.light,
                                label: Text('浅色'),
                                icon: Icon(Icons.light_mode),
                              ),
                              ButtonSegment(
                                value: ThemeModeValue.dark,
                                label: Text('深色'),
                                icon: Icon(Icons.dark_mode),
                              ),
                            ],
                            selected: {ThemeModeValue.fromInt(s.themeMode)},
                            onSelectionChanged: (set) {
                              final v = set.first;
                              ref
                                  .read(appSettingsProvider.notifier)
                                  .setThemeMode(v);
                            },
                            showSelectedIcon: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _SettingsTile.switchTile(
                    icon: Icons.palette_outlined,
                    tint: _Tint.secondary,
                    title: '动态取色',
                    subtitle:
                        '跟随壁纸生成配色（Material You），关闭后使用默认蓝',
                    value: s.dynamicColor,
                    onChanged: (v) => ref
                        .read(appSettingsProvider.notifier)
                        .updateSettings(dynamicColor: v),
                  ),
                  _SettingsTile(
                    icon: Icons.tune,
                    tint: _Tint.primary,
                    title: '首页卡片样式',
                    subtitle: '栏目显示、标签/摘要、标题行数与紧凑模式',
                    onTap: () => context.push('/settings/list-style'),
                  ),
                ],
              ),
              _SettingsSection(
                title: '转录与 AI',
                children: [
                  _SettingsTile.switchTile(
                    icon: Icons.content_paste_search_outlined,
                    tint: _Tint.primary,
                    title: '剪贴板链接检测',
                    subtitle:
                        '打开应用时检测剪贴板中的链接，弹窗提示一键转录',
                    value: s.clipboardDetection,
                    onChanged: (v) => ref
                        .read(appSettingsProvider.notifier)
                        .updateSettings(clipboardDetection: v),
                  ),
                  _SettingsTile(
                    icon: Icons.auto_awesome,
                    tint: _Tint.primary,
                    title: 'LLM API 设置',
                    subtitle: s.llmModel.isEmpty
                        ? '配置模型后可自动提取标签'
                        : '${s.llmModel} @ ${s.llmBaseUrl}',
                    onTap: () => context.push('/settings/llm'),
                  ),
                ],
              ),
              _SettingsSection(
                title: '回顾提醒',
                children: [
                  _SettingsTile.switchTile(
                    icon: Icons.phone_android,
                    tint: _Tint.primary,
                    title: '本地通知',
                    subtitle: 'App 离线也能准时响',
                    value: s.reminderChannels.contains('local'),
                    onChanged: (v) => _toggleChannel(ref, s, 'local', v),
                  ),
                  _SettingsTile.switchTile(
                    icon: Icons.email_outlined,
                    tint: _Tint.secondary,
                    title: 'SMTP 邮件',
                    subtitle: '到期时同步发到邮箱',
                    value: s.reminderChannels.contains('smtp'),
                    onChanged: (v) => _toggleChannel(ref, s, 'smtp', v),
                  ),
                  if (s.reminderChannels.contains('smtp'))
                    _SettingsTile(
                      icon: Icons.settings_suggest_outlined,
                      tint: _Tint.secondary,
                      title: '邮件服务器配置',
                      subtitle: s.smtpHost.isEmpty ? '未配置' : s.smtpHost,
                      indent: true,
                      onTap: () => context.push('/settings/smtp'),
                    ),
                  _SettingsTile.switchTile(
                    icon: Icons.calendar_month,
                    tint: _Tint.tertiary,
                    title: '日历事件',
                    subtitle: '写入系统日历',
                    value: s.reminderChannels.contains('calendar'),
                    onChanged: (v) => _toggleChannel(ref, s, 'calendar', v),
                  ),
                  _SettingsTile(
                    icon: Icons.timer_outlined,
                    tint: _Tint.primary,
                    title: '默认复习间隔',
                    subtitle:
                        '标记想学后 ${s.defaultReviewIntervalDays} 天提醒复习',
                    onTap: () => _pickReviewInterval(context, ref, s),
                  ),
                ],
              ),
              const _StorageCard(),
              _SettingsSection(
                title: '数据与备份',
                children: [
                  _SettingsTile(
                    icon: Icons.cookie_outlined,
                    tint: _Tint.secondary,
                    title: '抓取 Cookie 管理',
                    subtitle: '按域名匹配，抓取需要登录的网站',
                    onTap: () => context.push('/settings/cookies'),
                  ),
                  _SettingsTile(
                    icon: Icons.file_download,
                    tint: _Tint.primary,
                    title: '导出备份',
                    subtitle: '保存为可迁移文件夹',
                    onTap: () => _exportBackup(context, ref),
                  ),
                  _SettingsTile(
                    icon: Icons.file_upload,
                    tint: _Tint.tertiary,
                    title: '导入备份',
                    subtitle: '从之前的备份目录恢复',
                    onTap: () => _importBackup(context, ref),
                  ),
                ],
              ),
              _SettingsSection(
                title: '维护',
                children: [
                  _SettingsTile(
                    icon: Icons.delete_outline,
                    tint: _Tint.error,
                    title: '回收站',
                    subtitle: '恢复误删的收藏或彻底删除',
                    onTap: () => context.push('/settings/trash'),
                  ),
                  _SettingsTile(
                    icon: Icons.manage_search,
                    tint: _Tint.primary,
                    title: '重建搜索索引',
                    subtitle: '搜索结果异常或内容缺失时使用',
                    onTap: () => _runMaintenance(
                      context,
                      ref,
                      '重建搜索索引',
                      () => ref
                          .read(maintenanceServiceProvider)
                          .rebuildSearchIndex(),
                      (r) => '已重建 $r 篇收藏的索引',
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.cleaning_services_outlined,
                    tint: _Tint.error,
                    title: '清理孤儿图片',
                    subtitle: '删除已不存在收藏引用的图片目录',
                    onTap: () => _runMaintenance(
                      context,
                      ref,
                      '清理孤儿图片',
                      () =>
                          ref.read(maintenanceServiceProvider).cleanOrphanImages(),
                      (r) =>
                          '已清理 ${r.$1} 个目录，释放 ${_fmtBytes(r.$2)}',
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.text_snippet_outlined,
                    tint: _Tint.secondary,
                    title: '导出诊断日志',
                    subtitle: '保存为 JSONL 文件，可用于排查问题',
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        final logger = ref.read(appLoggerProvider);
                        if (logger.entries.isEmpty) {
                          messenger.showSnackBar(
                              const SnackBar(content: Text('暂无日志')));
                          return;
                        }
                        final path = await logger.exportToFile();
                        messenger.showSnackBar(
                            SnackBar(content: Text('已导出到 $path')));
                      } catch (e) {
                        messenger.showSnackBar(SnackBar(
                            content: Text('导出失败：$e'),
                            backgroundColor: Colors.red));
                      }
                    },
                  ),
                ],
              ),
              _SettingsSection(
                title: '关于',
                children: [
                  _SettingsTile(
                    icon: Icons.info_outline,
                    tint: _Tint.secondary,
                    title: '关于藏星',
                    subtitle: '版本信息、开源协议、致谢项目',
                    onTap: () => context.push('/settings/about'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickReviewInterval(
      BuildContext context, WidgetRef ref, AppSettings s) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('默认复习间隔'),
        children: [
          for (final d in _reviewIntervalOptions)
            RadioListTile<int>(
              value: d,
              groupValue: s.defaultReviewIntervalDays,
              onChanged: (v) => Navigator.pop(ctx, v),
              title: Text('$d 天'),
            ),
        ],
      ),
    );
    if (picked != null) {
      await ref
          .read(appSettingsProvider.notifier)
          .updateSettings(defaultReviewIntervalDays: picked);
    }
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final svc = ref.read(backupServiceProvider);
    try {
      final path = await svc.export();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已导出到 $path')));
      }
    } on BackupCancelledException catch (_) {
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入备份？'),
        content: const Text(
          '将覆盖现有收藏，建议先导出当前数据。导入完成后请重启 App 使数据库生效。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final svc = ref.read(backupServiceProvider);
    try {
      await svc.doImport();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入完成，请重启 App')),
        );
      }
    } on BackupCancelledException catch (_) {
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 跑一个维护任务：先确认，执行中显示进度，完成后报结果。
  Future<void> _runMaintenance<T>(
    BuildContext context,
    WidgetRef ref,
    String name,
    Future<T> Function() task,
    String Function(T) doneMessage,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name),
        content: Text('确定要执行「$name」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final messenger = ScaffoldMessenger.of(context);
    // 确认框退出动画进行中 Navigator 处于锁定状态，立刻 push 进度
    // 弹窗会抛断言（任务从未执行、界面看起来卡死），等动画结束再开
    await Future.delayed(const Duration(milliseconds: 300));

    BuildContext? dialogCtx;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogCtx = ctx;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Text('正在$name...'),
              ],
            ),
          ),
        );
      },
    );

    Future<void> closeDialog() async {
      // 任务可能瞬间完成（如索引行数很少），此时进度弹窗还在
      // 入场动画、Navigator 处于锁定状态，立刻 pop 会触发断言，
      // 等一帧再关
      await Future.delayed(const Duration(milliseconds: 150));
      if (dialogCtx != null && dialogCtx!.mounted) {
        Navigator.of(dialogCtx!).pop();
      }
    }

    try {
      final result = await task();
      await closeDialog();
      messenger.showSnackBar(SnackBar(content: Text(doneMessage(result))));
    } catch (e) {
      await closeDialog();
      messenger.showSnackBar(
        SnackBar(content: Text('$name失败：$e'), backgroundColor: Colors.red),
      );
    }
  }
}

String _fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  var b = bytes ~/ 1024;
  if (b < 1024) return '$b KB';
  b = b ~/ 1024;
  if (b < 1024) return '$b MB';
  return '${b ~/ 1024} GB';
}

/// 小节：标题 + 圆角卡片包裹的一组条目
class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Material(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

/// 图标底色调
enum _Tint { primary, secondary, tertiary, error }

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final _Tint tint;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool? switchValue;
  final ValueChanged<bool>? onChanged;
  /// 作为上一条目的次级操作时缩进（如 SMTP 服务器配置）
  final bool indent;

  const _SettingsTile({
    required this.icon,
    required this.tint,
    required this.title,
    this.subtitle,
    this.onTap,
    this.indent = false,
  })  : switchValue = null,
        onChanged = null;

  const _SettingsTile.switchTile({
    required this.icon,
    required this.tint,
    required this.title,
    this.subtitle,
    required ValueChanged<bool>? this.onChanged,
    required bool value,
  })  : switchValue = value,
        onTap = null,
        indent = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tint) {
      _Tint.primary => (scheme.primaryContainer, scheme.onPrimaryContainer),
      _Tint.secondary =>
        (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _Tint.tertiary => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _Tint.error => (scheme.errorContainer, scheme.onErrorContainer),
    };

    final leading = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: fg),
    );

    final trailing = switchValue != null
        ? Switch(value: switchValue!, onChanged: onChanged)
        : (onTap != null ? const Icon(Icons.chevron_right) : null);

    final tile = ListTile(
      leading: leading,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing,
      onTap: switchValue != null ? null : onTap,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );

    if (!indent) return tile;
    return Padding(
      padding: const EdgeInsets.only(left: 40),
      child: tile,
    );
  }
}

/// 存储统计卡片：收藏数 + 总占用 + 分类占比条
class _StorageCard extends ConsumerWidget {
  const _StorageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final stats = ref.watch(storageStatsProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              '存储',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Material(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: stats.when(
                loading: () => const Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (e, _) => Text('统计失败：$e'),
                data: (d) {
                  final total =
                      d.totalSizeBytes == 0 ? 1 : d.totalSizeBytes;
                  final segs = [
                    (
                      d.imagesSizeBytes,
                      scheme.primary,
                      '图片',
                    ),
                    (
                      d.contentSizeBytes,
                      scheme.tertiary,
                      '正文',
                    ),
                    (
                      d.metaSizeBytes,
                      scheme.secondary,
                      '元数据',
                    ),
                  ];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${d.collectionCount} 篇收藏',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          Text(
                            d.totalSizeFormatted,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 8,
                          child: Row(
                            children: [
                              for (final (size, color, _) in segs)
                                Expanded(
                                  flex: (size * 1000 / total).round().clamp(
                                      1, 1000),
                                  child: Container(color: color),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        children: [
                          for (final (size, color, label) in segs)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$label ${_fmtBytes(size)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
