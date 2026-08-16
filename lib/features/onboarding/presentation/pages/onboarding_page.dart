import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fav_app/core/constants/category_templates.dart';
import 'package:fav_app/features/collections/data/providers/category_repository_provider.dart';
import 'package:fav_app/features/settings/data/providers/app_settings_provider.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final PageController _ctrl = PageController(initialPage: 0);
  int _currentPage = 0;
  /// 模板页勾选的文件夹（默认全选）
  final Set<String> _selectedTemplate = kCategoryTemplate.keys.toSet();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    // 导入勾选的模板文件夹（失败不阻塞进入 App）
    if (_selectedTemplate.isNotEmpty) {
      try {
        await importCategoryTemplate(
          ref.read(categoryRepositoryProvider),
          _selectedTemplate,
        );
      } catch (_) {}
    }
    await ref
        .read(appSettingsProvider.notifier)
        .updateSettings(hasCompletedOnboarding: true);
    if (context.mounted) context.go('/collections');
  }

  @override
  Widget build(BuildContext context) {
    final blue = Colors.blue;
    final orange = Colors.orange;
    final purple = Colors.purple;
    final grey = Colors.grey.shade300;

    final pages = [
      (
        icon: Icons.inbox,
        color: blue,
        title: '一键收藏万物',
        desc: '把抖音 / 酷安 / 小黑盒里的好文章和热门评论，通过系统分享菜单统一保存到本地。原帖删了照样能读。'
      ),
      (
        icon: Icons.auto_awesome,
        color: orange,
        title: 'AI 自动转录排版',
        desc: '自动抓取正文 → LLM 排版 Markdown → 下载图片到本地。5 秒内得到干净可检索的阅读内容。'
      ),
      (
        icon: Icons.psychology,
        color: purple,
        title: '想学 + 间隔回顾',
        desc: '给收藏标上「想学」，按 1/3/7 天节奏提醒你复习，用本地通知 / 邮件 / 日历三种渠道推送到手。'
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                itemCount: pages.length + 1,
                onPageChanged: (i) {
                  setState(() => _currentPage = i);
                },
                itemBuilder: (_, i) {
                  // 第4页：文件夹模板选择（默认全选，可按需取消）
                  if (i == 3) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.folder_copy, size: 72, color: blue),
                          const SizedBox(height: 16),
                          Text(
                            '预置推荐文件夹',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '文件夹管「领域」，标签管「主题」。勾选要预置的文件夹，稍后可随时增删改名。',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 16),
                          ...kCategoryTemplate.entries.map(
                            (e) => CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(e.key),
                              subtitle: Text(
                                e.value,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              value: _selectedTemplate.contains(e.key),
                              onChanged: (v) => setState(() => v ?? false
                                  ? _selectedTemplate.add(e.key)
                                  : _selectedTemplate.remove(e.key)),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final p = pages[i];
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(p.icon, size: 120, color: p.color),
                        const SizedBox(height: 24),
                        Text(
                          p.title,
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          p.desc,
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => _complete(context, ref),
                    child: const Text('跳过'),
                  ),
                  Row(
                    children: List.generate(
                      pages.length + 1,
                      (i) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _currentPage ? blue : grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (_currentPage < 3) {
                        _ctrl.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      } else {
                        _complete(context, ref);
                      }
                    },
                    child: Text(_currentPage < 3 ? '下一步' : '进入 App'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
