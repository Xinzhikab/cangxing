import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fav_app/features/settings/data/providers/app_settings_provider.dart';

const _appIconChannel = MethodChannel('cn.cangxing.mobile/app_icon');

class AppIconPreset {
  final String key;
  final String label;
  final Color color;
  final IconData icon;

  const AppIconPreset({
    required this.key,
    required this.label,
    required this.color,
    this.icon = Icons.star_rounded,
  });
}

List<AppIconPreset> _buildOptions(ColorScheme scheme) => [
      AppIconPreset(
        key: 'default',
        label: '默认',
        color: scheme.primary,
      ),
      const AppIconPreset(
        key: 'blue',
        label: '蓝调',
        color: Color(0xFF2196F3),
      ),
      const AppIconPreset(
        key: 'orange',
        label: '暖橙',
        color: Color(0xFFFF9800),
      ),
      const AppIconPreset(
        key: 'green',
        label: '森林',
        color: Color(0xFF4CAF50),
      ),
      const AppIconPreset(
        key: 'night',
        label: '夜空',
        color: Color(0xFF37474F),
      ),
      const AppIconPreset(
        key: 'pink',
        label: '樱花',
        color: Color(0xFFE91E63),
      ),
    ];

class AppIconSettingsPage extends ConsumerWidget {
  const AppIconSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sAsync = ref.watch(appSettingsProvider);
    final scheme = Theme.of(context).colorScheme;
    final options = _buildOptions(scheme);

    return Scaffold(
      appBar: AppBar(title: const Text('应用图标')),
      body: sAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (s) {
          final currentIcon = s.appIcon;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: GridView.count(
              crossAxisCount: 3,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
              childAspectRatio: 0.85,
              children: options.map((opt) {
                final selected = currentIcon == opt.key;
                return GestureDetector(
                  onTap: () => _onSelect(context, ref, opt),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: opt.color,
                              borderRadius: BorderRadius.circular(16),
                              border: selected
                                  ? Border.all(
                                      color: scheme.primary,
                                      width: 3,
                                    )
                                  : null,
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: scheme.primary.withOpacity(0.4),
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Icon(
                              opt.icon,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                          if (selected)
                            const Positioned(
                              right: 0,
                              bottom: 0,
                              child: CircleAvatar(
                                radius: 12,
                                backgroundColor: Colors.white,
                                child: Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 22,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        opt.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w400,
                          color: selected
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  Future<void> _onSelect(
    BuildContext context,
    WidgetRef ref,
    AppIconPreset opt,
  ) async {
    final s = ref.read(appSettingsProvider).valueOrNull;
    if (s == null || s.appIcon == opt.key) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换应用图标'),
        content: Text('切换为「${opt.label}」图标？\n应用需重启后完全生效。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认切换'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await ref
          .read(appSettingsProvider.notifier)
          .updateSettings(appIcon: opt.key);
      try {
        await _appIconChannel.invokeMethod(
          'setAppIcon',
          {'iconName': opt.key},
        );
      } catch (_) {
        // 平台方法调用失败不影响偏好设置保存
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存图标设置，重启后生效')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
