import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fav_app/features/save/data/providers/share_input_provider.dart';
import 'package:fav_app/features/save/data/services/web_content_fetcher.dart';
import 'package:fav_app/features/settings/data/providers/app_settings_provider.dart';

class CollectionsShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const CollectionsShell({
    super.key,
    required this.navigationShell,
  });

  @override
  ConsumerState<CollectionsShell> createState() => _CollectionsShellState();
}

class _CollectionsShellState extends ConsumerState<CollectionsShell> {
  /// 上次已提示过的剪贴板内容：同一链接不重复弹窗（阅读 App 同款策略）
  static String? _lastPromptedClipboard;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 分享进入时剪贴板往往就是分享的那条链接，跳过检测避免双重弹窗；
      // 设置中关闭「剪贴板链接检测」则完全不检测
      final clipboardDetection = ref
              .read(appSettingsProvider)
              .valueOrNull
              ?.clipboardDetection ??
          true;
      if (clipboardDetection &&
          ref.read(pendingShareExtraProvider) == null) {
        _checkClipboard();
      }
      ref.listen<Object?>(pendingShareExtraProvider, (prev, next) {
        if (next != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            GoRouter.of(context).push('/save', extra: next);
          });
          ref.read(pendingShareExtraProvider.notifier).state = null;
        }
      });
    });
  }

  /// 启动时检测剪贴板：内容是可转录链接则弹窗，确认后带入保存页
  Future<void> _checkClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty ||
        text == _lastPromptedClipboard ||
        !WebContentFetcher.isLikelyUrl(text)) {
      return;
    }
    _lastPromptedClipboard = text;
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('检测到剪贴板链接'),
        content: Text(
          text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('转录'),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      GoRouter.of(context).push('/save', extra: text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: (index) {
          widget.navigationShell.goBranch(
            index,
            initialLocation: index == widget.navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark),
            label: '收藏',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: '想学',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: '分类',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
