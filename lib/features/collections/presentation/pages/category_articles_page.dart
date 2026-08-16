import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:fav_app/features/collections/data/providers/collections_list_controller.dart';

/// 分类浏览的文章列表：按文件夹路径 / 平台 / 作者 / 标签筛选展示收藏。
class CategoryArticlesPage extends ConsumerWidget {
  final List<String> categoryPath;
  final String? platform;
  final String? author;
  final String? tag;

  const CategoryArticlesPage({
    super.key,
    this.categoryPath = const [],
    this.platform,
    this.author,
    this.tag,
  });

  static String _platformLabel(String k) =>
      {'douyin': '抖音', 'xiaoheihe': '小黑盒', 'coolapk': '酷安', 'other': '其他'}[
          k] ??
      k;

  String _statusLabel(String k) =>
      {'learning': '想学', 'done': '已完成'}[k] ?? k;

  Color _statusColor(String s) {
    switch (s) {
      case 'learning':
        return Colors.orange;
      case 'done':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String get _title {
    if (tag != null) return '#$tag';
    if (platform != null) return _platformLabel(platform!);
    if (author != null && author!.isNotEmpty) return author!;
    return categoryPath.join(' / ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
      categoryArticlesProvider(
        CategoryArticlesFilter(
          categoryPath: categoryPath,
          platform: platform,
          author: author,
          tag: tag,
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Text(
                '这里还没有文章',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final c = list[i];
              return ListTile(
                onTap: () => context.push('/read/${c.id}'),
                leading: CircleAvatar(
                  child: Text(_platformLabel(c.sourcePlatform)[0]),
                ),
                title: Text(
                  c.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_platformLabel(c.sourcePlatform)} · ${c.author.isEmpty ? "佚名" : c.author} · ${DateFormat('yyyy-MM-dd').format(c.collectedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // 已读/未读功能已移除：仅「想学 / 已完成」显示状态徽标
                trailing: (c.status == 'learning' || c.status == 'done')
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _statusColor(c.status),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _statusLabel(c.status),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      )
                    : const Icon(Icons.chevron_right),
              );
            },
          );
        },
      ),
    );
  }
}

/// 打开文章列表页的参数。
class CategoryArticlesArgs {
  final List<String> categoryPath;
  final String? platform;
  final String? author;
  final String? tag;

  const CategoryArticlesArgs({
    this.categoryPath = const [],
    this.platform,
    this.author,
    this.tag,
  });
}
