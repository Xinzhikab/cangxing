import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fav_app/features/settings/data/providers/list_field_style_provider.dart';

/// 首页文章卡片样式设置页：预设方案 + 栏目开关 + 排版参数。
/// 整页 ListView 滚动，任何屏高都不会溢出。
class ListStyleSettingsPage extends ConsumerWidget {
  const ListStyleSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(listFieldStyleProvider);
    final notifier = ref.read(listFieldStyleProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('首页卡片样式')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // ---------- 预设方案 ----------
          Text('预设方案', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in kListFieldPresets.entries)
                ActionChip(
                  label: Text(e.key),
                  onPressed: () => notifier.applyPreset(e.value),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ---------- 栏目显示 ----------
          Text('栏目显示', style: theme.textTheme.titleSmall),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('图标'),
            subtitle: const Text('左侧圆形平台图标'),
            value: style.showIcon,
            onChanged: (v) => notifier.update(showIcon: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('平台'),
            subtitle: const Text('副标题中的来源平台'),
            value: style.showPlatform,
            onChanged: (v) => notifier.update(showPlatform: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('作者'),
            subtitle: const Text('副标题中的作者名'),
            value: style.showAuthor,
            onChanged: (v) => notifier.update(showAuthor: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('时间'),
            subtitle: const Text('副标题中的收藏时间'),
            value: style.showTime,
            onChanged: (v) => notifier.update(showTime: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('分类'),
            subtitle: const Text('副标题中的文件夹路径'),
            value: style.showCategory,
            onChanged: (v) => notifier.update(showCategory: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('标签'),
            subtitle: const Text('卡片底部的标签 chips'),
            value: style.showTags,
            onChanged: (v) => notifier.update(showTags: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('正文摘要'),
            subtitle: const Text('标题下方的正文首行预览'),
            value: style.showSnippet,
            onChanged: (v) => notifier.update(showSnippet: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('状态徽标'),
            subtitle: const Text('「想学 / 已完成」角标'),
            value: style.showStatusBadge,
            onChanged: (v) => notifier.update(showStatusBadge: v),
          ),
          const SizedBox(height: 8),

          // ---------- 排版 ----------
          Text('排版', style: theme.textTheme.titleSmall),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('标题行数：${style.titleLines} 行'),
            subtitle: Slider(
              value: style.titleLines.toDouble(),
              min: 1,
              max: 3,
              divisions: 2,
              label: '${style.titleLines} 行',
              onChanged: (v) => notifier.update(titleLines: v.round()),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('紧凑模式'),
            subtitle: const Text('减小卡片内边距，列表更密'),
            value: style.compact,
            onChanged: (v) => notifier.update(compact: v),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '设置即时生效并自动保存',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
