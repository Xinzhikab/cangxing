import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fav_app/features/settings/data/providers/cookie_provider.dart';

class CookiesPage extends ConsumerStatefulWidget {
  const CookiesPage({super.key});

  @override
  ConsumerState<CookiesPage> createState() => _CookiesPageState();
}

class _CookiesPageState extends ConsumerState<CookiesPage> {
  static const Map<String, String> _presets = {
    '酷安': 'coolapk.com',
    '知乎': 'zhihu.com',
    '哔哩哔哩': 'bilibili.com',
    '微博': 'weibo.com',
    '豆瓣': 'douban.com',
    'CSDN': 'csdn.net',
    '掘金': 'juejin.cn',
    '小红书': 'xiaohongshu.com',
    '小黑盒': 'xiaoheihe.cn',
    '微信读书': 'weread.qq.com',
  };

  void _editDialog(SiteCookie seed) {
    final domainCtrl = TextEditingController(text: seed.domain);
    final cookieCtrl = TextEditingController(text: seed.cookie);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(seed.domain.isEmpty ? '新增 Cookie' : '编辑 Cookie'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: domainCtrl,
              decoration: const InputDecoration(
                labelText: '域名',
                hintText: '如 coolapk.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cookieCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Cookie',
                hintText: 'uid=xxx; token=yyy',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await ref.read(cookieListProvider.notifier).upsert(
                    seed,
                    SiteCookie(
                      domain: domainCtrl.text.trim(),
                      cookie: cookieCtrl.text.trim(),
                    ),
                  );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cookiesAsync = ref.watch(cookieListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('抓取 Cookie 管理'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '常用网站预设（点击填入域名）',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presets.entries.map((e) {
                return ActionChip(
                  label: Text(e.key),
                  onPressed: () => _editDialog(
                    SiteCookie(domain: e.value, cookie: ''),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: cookiesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
              data: (cookies) => cookies.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          '没有配置 Cookie。可从上方预设快速添加，或点右下角 + 按域名添加，抓网页时会自动匹配填入 Cookie 请求头',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: cookies.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final c = cookies[i];
                        return ListTile(
                          leading: const Icon(Icons.cookie, color: Colors.brown),
                          title: Text(
                            c.domain,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            c.cookie.length > 40
                                ? '${c.cookie.substring(0, 40)}…'
                                : c.cookie,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          onTap: () => _editDialog(c),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () async {
                              await ref
                                  .read(cookieListProvider.notifier)
                                  .remove(c.domain);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _editDialog(const SiteCookie(domain: '', cookie: '')),
      ),
    );
  }
}
