import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:fav_app/features/collections/data/providers/collection_repository_provider.dart';
import 'package:fav_app/features/collections/data/providers/trash_provider.dart';

class TrashPage extends ConsumerWidget {
  const TrashPage({super.key});

  static final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  Future<void> _restore(WidgetRef ref, String id) async {
    final repo = ref.read(collectionRepositoryProvider);
    await repo.restore(id);
    ref.invalidate(trashListProvider);
  }

  Future<void> _permanentDelete(
      BuildContext context, WidgetRef ref, String id, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除'),
        content: Text('确定要彻底删除「$title」吗？此操作不可撤销，相关文件将被永久删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repo = ref.read(collectionRepositoryProvider);
    await repo.permanentDelete(id);
    ref.invalidate(trashListProvider);
  }

  Future<void> _emptyTrash(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站'),
        content: const Text('此操作不可撤销，确定要清空所有已删除的收藏吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repo = ref.read(collectionRepositoryProvider);
    await repo.emptyTrash();
    ref.invalidate(trashListProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashItems = ref.watch(trashListProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: '清空回收站',
            onPressed: () => _emptyTrash(context, ref),
          ),
        ],
      ),
      body: trashItems.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline,
                      size: 56, color: scheme.onSurfaceVariant.withOpacity(0.5)),
                  const SizedBox(height: 12),
                  Text(
                    '回收站为空',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (ctx, i) {
              final c = items[i];
              final deletedAt = c.deletedAt;
              final deletedText = deletedAt != null
                  ? '删除于 ${_dateFormat.format(DateTime.fromMillisecondsSinceEpoch(deletedAt))}'
                  : '删除时间未知';
              return ListTile(
                leading: Icon(Icons.delete_outline,
                    color: scheme.onSurfaceVariant.withOpacity(0.6)),
                title: Text(
                  c.title.isEmpty ? '(无标题)' : c.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  deletedText,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.restore),
                      tooltip: '恢复',
                      onPressed: () => _restore(ref, c.id),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      tooltip: '彻底删除',
                      onPressed: () =>
                          _permanentDelete(context, ref, c.id, c.title),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
