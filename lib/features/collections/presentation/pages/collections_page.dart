import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/features/collections/data/models/category.dart';
import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/collections/data/providers/category_tree_provider.dart';
import 'package:fav_app/features/collections/data/providers/category_repository_provider.dart';
import 'package:fav_app/features/collections/data/providers/collections_list_controller.dart';
import 'package:fav_app/features/collections/data/providers/collection_repository_provider.dart';
import 'package:fav_app/features/settings/data/providers/list_field_style_provider.dart';

final selectionModeProvider = StateProvider<bool>((ref) => false);
final selectedIdsProvider = StateProvider<Set<String>>((ref) => {});

class CollectionsPage extends ConsumerStatefulWidget {
  const CollectionsPage({super.key});

  @override
  ConsumerState<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends ConsumerState<CollectionsPage> {
  late final TextEditingController _searchCtrl;
  late final ScrollController _scrollCtrl;
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _scrollCtrl = ScrollController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectionMode = ref.watch(selectionModeProvider);
    return Scaffold(
      appBar: selectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(),
      drawer: selectionMode ? null : const _CategoryDrawer(),
      body: Stack(
        children: [
          Column(
            children: [
              if (!selectionMode) const _FilterChipRow(),
              Expanded(child: _ListBody(controller: _scrollCtrl)),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 100,
            child: _buildScrollToTopBtn(),
          ),
        ],
      ),
      floatingActionButton: selectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/save'),
              icon: const Icon(Icons.add),
              label: const Text('手动添加'),
            ),
    );
  }

  Widget _buildScrollToTopBtn() {
    return AnimatedBuilder(
      animation: _scrollCtrl,
      builder: (ctx, _) {
        final show = _scrollCtrl.hasClients && _scrollCtrl.offset > 400;
        return AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !show,
            child: FloatingActionButton.small(
              heroTag: 'scroll_to_top',
              onPressed: () => _scrollCtrl.animateTo(
                0,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
              ),
              child: const Icon(Icons.arrow_upward),
            ),
          ),
        );
      },
    );
  }

  AppBar _buildNormalAppBar() {
    final scheme = Theme.of(context).colorScheme;
    if (_searchOpen) {
      final history = ref.watch(searchHistoryProvider);
      return AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索标题或正文...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) {
                final f = ref
                    .read(collectionsFilterProvider.notifier)
                    .update((s) => s.copyWith(keyword: v));
                ref.read(collectionsListProvider.notifier).setFilter(f);
              },
              onSubmitted: (v) {
                ref.read(searchHistoryProvider.notifier).add(v);
              },
            ),
            if (history.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: history.length,
                    separatorBuilder: (_, i) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      return InputChip(
                        label: Text(history[i]),
                        onPressed: () {
                          _searchCtrl.text = history[i];
                          final f = ref
                              .read(collectionsFilterProvider.notifier)
                              .update((s) => s.copyWith(keyword: history[i]));
                          ref
                              .read(collectionsListProvider.notifier)
                              .setFilter(f);
                        },
                        onDeleted: () =>
                            ref.read(searchHistoryProvider.notifier).removeAt(i),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: '清除历史',
              onPressed: () =>
                  ref.read(searchHistoryProvider.notifier).clear(),
            ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: '关闭搜索',
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              _searchCtrl.clear();
              final f = ref
                  .read(collectionsFilterProvider.notifier)
                  .update((s) => s.copyWith(keyword: ''));
              ref.read(collectionsListProvider.notifier).setFilter(f);
              setState(() => _searchOpen = false);
            },
          ),
        ],
        bottom: history.isNotEmpty
            ? const PreferredSize(
                preferredSize: Size.fromHeight(0),
                child: SizedBox.shrink(),
              )
            : null,
      );
    }
    return AppBar(
      title: GestureDetector(
        onTap: () => setState(() => _searchOpen = true),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                _searchCtrl.text.trim().isEmpty
                    ? '搜索标题或正文...'
                    : _searchCtrl.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.checklist),
          tooltip: '批量选择',
          onPressed: () =>
              ref.read(selectionModeProvider.notifier).state = true,
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () => context.push('/save'),
        ),
      ],
    );
  }

  AppBar _buildSelectionAppBar() {
    final selected = ref.watch(selectedIdsProvider);
    final list = ref.watch(collectionsListProvider).valueOrNull ?? [];
    final allSelected = selected.length >= list.length && list.isNotEmpty;

    void exitSelection() {
      ref.read(selectionModeProvider.notifier).state = false;
      ref.read(selectedIdsProvider.notifier).state = {};
    }

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: exitSelection,
        tooltip: '退出多选',
      ),
      title: Text('已选 ${selected.length} 项'),
      actions: [
        IconButton(
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          tooltip: allSelected ? '取消全选' : '全选',
          onPressed: () {
            ref.read(selectedIdsProvider.notifier).state = allSelected
                ? <String>{}
                : list.map((c) => c.id).toSet();
          },
        ),
        IconButton(
          icon: const Icon(Icons.label_outline),
          tooltip: '批量加标签',
          onPressed:
              selected.isEmpty ? null : () => _batchAddTags(selected.toList()),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_outlined),
          tooltip: '批量改状态',
          onPressed:
              selected.isEmpty ? null : () => _batchUpdateStatus(selected.toList()),
        ),
        IconButton(
          icon: const Icon(Icons.drive_file_move_outline),
          tooltip: '移动到分类',
          onPressed: selected.isEmpty ? null : () => _batchMove(exitSelection),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: '删除',
          onPressed: selected.isEmpty ? null : () => _batchDelete(exitSelection),
        ),
        IconButton(
          icon: const Icon(Icons.push_pin_outlined),
          tooltip: '批量置顶',
          onPressed:
              selected.isEmpty ? null : () => _batchTogglePin(selected.toList()),
        ),
      ],
    );
  }

  Future<void> _batchDelete(VoidCallback onDone) async {
    final ids = ref.read(selectedIdsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除 ${ids.length} 篇收藏？'),
        content: const Text('会移到回收站（保留文件），可在【设置→回收站】恢复，或彻底删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(collectionRepositoryProvider);
    for (final id in ids) {
      try {
        await repo.delete(id);
      } catch (e, st) {
        debugPrint('[CollectionsPage] $e\n$st');
      }
    }
    ref.invalidate(collectionsListProvider);
    ref.invalidate(groupStatsProvider);
    ref.invalidate(allTagsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 ${ids.length} 篇收藏，可在回收站恢复')),
      );
    }
    onDone();
  }

  Future<void> _batchAddTags(List<String> ids) async {
    final tagCtrl = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('给 ${ids.length} 篇收藏加标签'),
        content: TextField(
          controller: tagCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '多个标签用逗号分隔',
            hintText: '标签1, 标签2, 标签3',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, tagCtrl.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (input == null) return;
    final tags = input
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (tags.isEmpty) return;

    if (ids.length > 20 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('正在给 ${ids.length} 篇收藏加标签...')),
      );
    }

    final repo = ref.read(collectionRepositoryProvider);
    var done = 0;
    for (final id in ids) {
      try {
        final col = await repo.get(id);
        if (col == null) continue;
        final newTags = <String>{...col.tags, ...tags};
        await repo.update(col.copyWith(tags: newTags.toList()));
        done++;
      } catch (e, st) {
        debugPrint('[CollectionsPage] addTag: $e\n$st');
      }
    }
    ref.invalidate(collectionsListProvider);
    ref.invalidate(allTagsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已给 $done 篇收藏添加 ${tags.length} 个标签')),
      );
    }
  }

  Future<void> _batchUpdateStatus(List<String> ids) async {
    CollectionStatus? picked = await showDialog<CollectionStatus>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('更新 ${ids.length} 篇状态为...'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, CollectionStatus.unread),
            child: const Row(
              children: [
                Icon(Icons.mark_email_unread, color: Colors.grey),
                SizedBox(width: 12),
                Text('未读'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, CollectionStatus.learning),
            child: const Row(
              children: [
                Icon(Icons.school, color: Colors.orange),
                SizedBox(width: 12),
                Text('学习中 / 想学'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, CollectionStatus.done),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 12),
                Text('已完成'),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null) return;
    final targetStatus = CollectionEnums.statusToSql(picked)!;

    if (ids.length > 20 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('正在更新 ${ids.length} 篇状态...')),
      );
    }

    final repo = ref.read(collectionRepositoryProvider);
    var done = 0;
    for (final id in ids) {
      try {
        final col = await repo.get(id);
        if (col == null) continue;
        await repo.update(col.copyWith(status: targetStatus));
        done++;
      } catch (e, st) {
        debugPrint('[CollectionsPage] updateStatus: $e\n$st');
      }
    }
    ref.invalidate(collectionsListProvider);
    ref.invalidate(groupStatsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '已更新 $done 篇状态为「${CollectionEnums.statusLabel(picked)}」')),
      );
    }
  }

  Future<void> _batchMove(VoidCallback onDone) async {
    final ids = ref.read(selectedIdsProvider);
    final allCategories = ref.read(categoriesListProvider).valueOrNull ?? [];
    final byId = {for (final c in allCategories) c.id: c};

    final paths = <List<String>>[];
    for (final c in allCategories) {
      final temp = <String>[c.name];
      var pid = c.parentId;
      while (pid != null && byId.containsKey(pid)) {
        temp.insert(0, byId[pid]!.name);
        pid = byId[pid]!.parentId;
      }
      paths.add(temp);
    }

    List<String>? target;
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('移动 ${ids.length} 篇到...'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                RadioListTile<List<String>?>(
                  value: null,
                  groupValue: target,
                  onChanged: (v) => setState(() => target = v),
                  title: const Text('未分类'),
                ),
                for (final path in paths)
                  RadioListTile<List<String>>(
                    value: path,
                    groupValue: target,
                    onChanged: (v) => setState(() => target = v),
                    title: Text(path.join('/')),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, target ?? ['未分类']),
              child: const Text('移动'),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;

    final repo = ref.read(collectionRepositoryProvider);
    var moved = 0;
    for (final id in ids) {
      try {
        final col = await repo.get(id);
        if (col == null) continue;
        await repo.update(col.copyWith(category: picked));
        moved++;
      } catch (e, st) {
        debugPrint('[CollectionsPage] $e\n$st');
      }
    }
    ref.invalidate(collectionsListProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已移动 $moved 篇到 ${picked.join('/')}')),
      );
    }
    onDone();
  }

  Future<void> _batchTogglePin(List<String> ids) async {
    final picked = await showDialog<bool>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('批量置顶 ${ids.length} 篇'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Row(
              children: [
                Icon(Icons.push_pin, color: Colors.orange),
                SizedBox(width: 12),
                Text('全部置顶'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Row(
              children: [
                Icon(Icons.push_pin_outlined),
                SizedBox(width: 12),
                Text('全部取消置顶'),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null) return;
    final repo = ref.read(collectionRepositoryProvider);
    await repo.setPinnedBatch(ids, pinned: picked);
    ref.invalidate(collectionsListProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(picked ? '已置顶 ${ids.length} 篇' : '已取消 ${ids.length} 篇置顶')),
      );
    }
  }
}

class _CategoryDrawer extends ConsumerStatefulWidget {
  const _CategoryDrawer();

  @override
  ConsumerState<_CategoryDrawer> createState() => _CategoryDrawerState();
}

class _CategoryDrawerState extends ConsumerState<_CategoryDrawer> {
  List<String> _resolvePath(CategoryNode node, List<Category> allCategories) {
    final path = <String>[];
    String? currentParentId = node.category.parentId;

    final byId = {for (final c in allCategories) c.id: c};
    final idToName = <String, String>{};
    idToName[node.category.id] = node.category.name;

    while (currentParentId != null && byId.containsKey(currentParentId)) {
      final parent = byId[currentParentId]!;
      idToName[parent.id] = parent.name;
      currentParentId = parent.parentId;
    }

    final orderedIds = <String>[];
    String? pid = node.category.parentId;
    final tempList = <String>[];
    tempList.add(node.category.name);
    while (pid != null && byId.containsKey(pid)) {
      final parent = byId[pid]!;
      tempList.insert(0, parent.name);
      pid = parent.parentId;
    }
    return tempList;
  }

  List<ListTile> _buildNodeTile(
    BuildContext context,
    WidgetRef ref,
    CategoryNode node,
    List<Category> allCategories, {
    required int depth,
  }) {
    final tiles = <ListTile>[];
    tiles.add(ListTile(
      leading: Icon(
        node.children.isNotEmpty ? Icons.folder : Icons.folder_open,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Padding(
        padding: EdgeInsets.only(left: depth * 16.0),
        child: Text(node.category.name),
      ),
      onTap: () {
        final path = _resolvePath(node, allCategories);
        ref.read(selectedCategoryPathProvider.notifier).state = path;
        final f = ref
            .read(collectionsFilterProvider.notifier)
            .update((s) => s.copyWith(categoryPath: path));
        ref.read(collectionsListProvider.notifier).setFilter(f);
        Navigator.pop(context);
      },
      onLongPress: () {
        Navigator.pop(context);
        showModalBottomSheet(
          context: context,
          builder: (_) => _FolderActionsSheet(node: node),
        );
      },
    ));
    for (final child in node.children) {
      tiles.addAll(_buildNodeTile(
        context,
        ref,
        child,
        allCategories,
        depth: depth + 1,
      ));
    }
    return tiles;
  }

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(categoryTreeProvider);
    return Drawer(
      child: tree.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('加载失败')),
        data: (roots) {
          final allCategories = ref.watch(categoriesListProvider).valueOrNull ?? [];
          return Column(
            children: [
              UserAccountsDrawerHeader(
                accountName: const Text('收藏夹'),
                accountEmail: const Text('本地收藏管理'),
                currentAccountPicture:
                    const CircleAvatar(child: Icon(Icons.folder_open)),
              ),
              ListTile(
                leading: const Icon(Icons.inbox),
                title: const Text('全部收藏'),
                onTap: () {
                  ref.read(selectedCategoryPathProvider.notifier).state = [];
                  final f = ref
                      .read(collectionsFilterProvider.notifier)
                      .update((s) => s.copyWith(categoryPath: null));
                  ref.read(collectionsListProvider.notifier).setFilter(f);
                  Navigator.pop(context);
                },
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  children: roots
                      .map((n) => _buildNodeTile(
                            context,
                            ref,
                            n,
                            allCategories,
                            depth: 0,
                          ))
                      .expand((x) => x)
                      .toList(),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.create_new_folder),
                title: const Text('新建文件夹'),
                onTap: () => _showNewFolderDialog(
                  context,
                  ref,
                  parentId: null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FolderActionsSheet extends ConsumerWidget {
  final CategoryNode node;

  const _FolderActionsSheet({required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.create_new_folder),
          title: const Text('在下面新建子文件夹'),
          onTap: () {
            Navigator.pop(context);
            _showNewFolderDialog(
              context,
              ref,
              parentId: node.category.id,
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.edit),
          title: const Text('重命名'),
          onTap: () {
            Navigator.pop(context);
            _showRenameDialog(context, ref, node.category);
          },
        ),
        ListTile(
          leading: const Icon(Icons.drive_file_move),
          title: const Text('移动此目录下的收藏到其他目录'),
          onTap: () {
            Navigator.pop(context);
            _showMoveDialog(context, ref, node.category);
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete, color: Colors.red),
          title: const Text(
            '删除（收藏回退到未分类）',
            style: TextStyle(color: Colors.red),
          ),
          onTap: () async {
            Navigator.pop(context);
            await Future.delayed(const Duration(milliseconds: 300));
            if (!context.mounted) return;
            BuildContext? dialogCtx;
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (dCtx) {
                dialogCtx = dCtx;
                return PopScope(
                  canPop: false,
                  child: AlertDialog(
                    content: Row(
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(width: 20),
                        Text('正在删除「${node.category.name}」...'),
                      ],
                    ),
                  ),
                );
              },
            );
            final repo = ref.read(categoryRepositoryProvider);
            try {
              await repo.delete(node.category.id);
            } finally {
              await Future.delayed(const Duration(milliseconds: 150));
              if (dialogCtx != null && dialogCtx!.mounted) {
                Navigator.of(dialogCtx!).pop();
              }
            }
            ref.invalidate(categoriesListProvider);
            ref.invalidate(collectionsListProvider);
          },
        ),
      ],
    );
  }
}

Future<void> _showNewFolderDialog(
  BuildContext context,
  WidgetRef ref, {
  String? parentId,
}) async {
  final nameCtrl = TextEditingController();
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('新建文件夹'),
      content: TextField(
        controller: nameCtrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: '名称'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            if (nameCtrl.text.trim().isEmpty) return;
            final repo = ref.read(categoryRepositoryProvider);
            await repo.create(Category(
              id: const Uuid().v4(),
              name: nameCtrl.text.trim(),
              parentId: parentId,
              sortOrder: 0,
              createdAt: DateTime.now(),
            ));
            ref.invalidate(categoriesListProvider);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('创建'),
        ),
      ],
    ),
  );
}

Future<void> _showRenameDialog(
  BuildContext context,
  WidgetRef ref,
  Category category,
) async {
  final nameCtrl = TextEditingController(text: category.name);
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('重命名文件夹'),
      content: TextField(
        controller: nameCtrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: '名称'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            if (nameCtrl.text.trim().isEmpty) return;
            final repo = ref.read(categoryRepositoryProvider);
            await repo.update(category.copyWith(name: nameCtrl.text.trim()));
            ref.invalidate(categoriesListProvider);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

Future<List<String>?> _showMoveDialog(
  BuildContext context,
  WidgetRef ref,
  Category sourceCategory,
) async {
  final allCategories = ref.read(categoriesListProvider).valueOrNull ?? [];
  final allCategoryNames = <List<String>>[];

  final byParent = <String?, List<Category>>{};
  for (final c in allCategories) {
    byParent.putIfAbsent(c.parentId, () => []).add(c);
  }
  final byId = {for (final c in allCategories) c.id: c};

  List<String> _buildPathForCategory(Category cat) {
    final path = <String>[];
    final temp = <String>[cat.name];
    String? pid = cat.parentId;
    while (pid != null && byId.containsKey(pid)) {
      final p = byId[pid]!;
      temp.insert(0, p.name);
      pid = p.parentId;
    }
    return temp;
  }

  for (final c in allCategories) {
    if (c.id != sourceCategory.id) {
      allCategoryNames.add(_buildPathForCategory(c));
    }
  }

  List<String>? selectedPath;

  return showDialog<List<String>?>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('选择目标目录'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<List<String>?>(
                value: null,
                groupValue: selectedPath,
                onChanged: (v) => setState(() => selectedPath = v),
                title: const Text('未分类'),
              ),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: allCategoryNames.length,
                  itemBuilder: (_, i) {
                    final path = allCategoryNames[i];
                    return RadioListTile<List<String>>(
                      value: path,
                      groupValue: selectedPath,
                      onChanged: (v) => setState(() => selectedPath = v),
                      title: Text(path.join('/')),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final repo = ref.read(collectionRepositoryProvider);
              final byIdMap = {for (final c in allCategories) c.id: c};
              List<String>? sourcePath;
              final temp = <String>[sourceCategory.name];
              String? pid = sourceCategory.parentId;
              while (pid != null && byIdMap.containsKey(pid)) {
                final p = byIdMap[pid]!;
                temp.insert(0, p.name);
                pid = p.parentId;
              }
              sourcePath = temp;

              final list = await repo.list(categoryPath: sourcePath);
              final newPath = selectedPath ?? ['未分类'];
              for (final c in list) {
                await repo.update(c.copyWith(category: newPath));
              }
              ref.invalidate(collectionsListProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('移动'),
          ),
        ],
      ),
    ),
  );
}

class _FilterChipRow extends StatelessWidget {
  const _FilterChipRow();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Consumer(
        builder: (_, ref, __) {
          final filter = ref.watch(collectionsFilterProvider);
          final groups = ref.watch(groupStatsProvider);
          return Row(
            children: [
              FilterChip(
                label: const Text('全部状态'),
                selected: filter.status == null,
                onSelected: (_) => _updFilter(
                  ref,
                  filter.copyWith(status: null),
                ),
              ),
              ...groups.valueOrNull?['statuses']?.map((m) {
                    final k = m.keys.first;
                    final cnt = m.values.first;
                    final statusEnum = CollectionEnums.statusFromSql(k);
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: FilterChip(
                        label: Text('${_statusLabel(statusEnum)} $cnt'),
                        selected: filter.status == statusEnum,
                        onSelected: (_) => _updFilter(
                          ref,
                          filter.copyWith(status: statusEnum),
                        ),
                      ),
                    );
                  }).toList(growable: false) ??
                  [],
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('全部平台'),
                selected: filter.platform == null,
                onSelected: (_) => _updFilter(
                  ref,
                  filter.copyWith(platform: null),
                ),
              ),
              ...groups.valueOrNull?['platforms']?.take(4).map((m) {
                    final k = m.keys.first;
                    final cnt = m.values.first;
                    final platformEnum = CollectionEnums.platformFromSql(k);
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: FilterChip(
                        label: Text('${_platformLabel(platformEnum)} $cnt'),
                        selected: filter.platform == platformEnum,
                        onSelected: (_) => _updFilter(
                          ref,
                          filter.copyWith(platform: platformEnum),
                        ),
                      ),
                    );
                  }).toList(growable: false) ??
                  [],
              const SizedBox(width: 12),
              PopupMenuButton<CollectionSortField>(
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: CollectionSortField.collectedAt,
                    child: Text('按收藏时间'),
                  ),
                  const PopupMenuItem(
                    value: CollectionSortField.publishedAt,
                    child: Text('按原帖时间'),
                  ),
                  const PopupMenuItem(
                    value: CollectionSortField.title,
                    child: Text('按标题'),
                  ),
                ],
                onSelected: (v) => _updFilter(
                  ref,
                  filter.copyWith(sortBy: v),
                ),
                child: Chip(
                  avatar: const Icon(Icons.sort),
                  label: Text(_sortLabel(filter.sortBy)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  filter.descending
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                ),
                onPressed: () => _updFilter(
                  ref,
                  filter.copyWith(descending: !filter.descending),
                ),
              ),
              const SizedBox(width: 8),
              Builder(
                builder: (context) {
                  final scheme = Theme.of(context).colorScheme;
                  return FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.push_pin,
                          size: 14,
                          color: filter.pinnedOnly
                              ? scheme.onPrimaryContainer
                              : null,
                        ),
                        const SizedBox(width: 4),
                        const Text('置顶'),
                      ],
                    ),
                    selected: filter.pinnedOnly,
                    onSelected: (v) {
                      _updFilter(ref, filter.copyWith(pinnedOnly: v));
                    },
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

void _updFilter(WidgetRef ref, CollectionsFilter f) {
  ref.read(collectionsFilterProvider.notifier).state = f;
  ref.read(collectionsListProvider.notifier).setFilter(f);
}

String _statusLabel(CollectionStatus? s) =>
    CollectionEnums.statusLabel(s);

String _platformLabel(SourcePlatform? p) =>
    CollectionEnums.platformLabel(p);

String _sortLabel(CollectionSortField s) =>
    CollectionEnums.sortLabel(s);

class _ListBody extends StatelessWidget {
  final ScrollController? controller;

  const _ListBody({this.controller});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (_, ref, __) {
        final listAsync = ref.watch(collectionsListProvider);
        return listAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败：$e')),
          data: (list) {
            return RefreshIndicator(
              onRefresh: () async {
                await ref.read(collectionsListProvider.notifier).refresh();
                ref.invalidate(groupStatsProvider);
              },
              child: list.isEmpty
                  ? ListView(
                      controller: controller,
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.28,
                        ),
                        Icon(
                          Icons.inbox,
                          size: 80,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        const Center(child: Text('暂无收藏，点击 + 添加')),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            '或在其他 App 点「分享」→「收藏」保存',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      controller: controller,
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final c = list[i];
                        return _CollectionTile(c: c);
                      },
                    ),
            );
          },
        );
      },
    );
  }
}

class _CollectionTile extends StatelessWidget {
  final Collection c;

  const _CollectionTile({required this.c});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (_, ref, __) {
        final selectionMode = ref.watch(selectionModeProvider);
        final selected = ref.watch(selectedIdsProvider).contains(c.id);
        final fieldStyle = ref.watch(listFieldStyleProvider);
        final scheme = Theme.of(context).colorScheme;

        void toggleSelect() {
          final ids = Set<String>.from(ref.read(selectedIdsProvider));
          selected ? ids.remove(c.id) : ids.add(c.id);
          ref.read(selectedIdsProvider.notifier).state = ids;
        }

        final subtitleParts = <String>[
          if (fieldStyle.showPlatform)
            _platformLabel(CollectionEnums.platformFromSql(c.sourcePlatform)),
          if (fieldStyle.showAuthor)
            c.author.isEmpty ? '佚名' : c.author,
          if (fieldStyle.showTime)
            DateFormat('yyyy-MM-dd HH:mm').format(c.collectedAt),
          if (fieldStyle.showCategory && c.category.isNotEmpty)
            c.category.join('/'),
        ];
        final hasSubtitle = subtitleParts.isNotEmpty;

        final snippet = fieldStyle.showSnippet
            ? _extractSnippet(c.contentMd)
            : '';

        Widget? leading;
        if (selectionMode) {
          leading = Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          );
        } else if (fieldStyle.showIcon) {
          leading = CircleAvatar(
            backgroundColor: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: Text(_platformLabel(
                    CollectionEnums.platformFromSql(c.sourcePlatform))[0]),
          );
        }

        final statusEnum = CollectionEnums.statusFromSql(c.status);
        final showBadge = !selectionMode &&
            fieldStyle.showStatusBadge &&
            (statusEnum == CollectionStatus.learning ||
                statusEnum == CollectionStatus.done);

        final titleBlockContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.pinnedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 4),
                    child: Icon(
                      Icons.push_pin,
                      size: 14,
                      color: scheme.primary,
                    ),
                  ),
                Expanded(
                  child: Text(
                    c.title,
                    maxLines: fieldStyle.titleLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (snippet.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                snippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            if (fieldStyle.showTags && c.tags.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final t in c.tags.take(4))
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .secondaryContainer
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '#$t',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );

        Widget? trailing;
        if (!selectionMode) {
          trailing = PopupMenuButton<_TileAction>(
            onSelected: (action) async {
              final repo = ref.read(collectionRepositoryProvider);
              switch (action) {
                case _TileAction.togglePin:
                  await repo.togglePin(c.id);
                  ref.invalidate(collectionsListProvider);
                  break;
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem<_TileAction>(
                value: _TileAction.togglePin,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(c.pinnedAt != null
                      ? Icons.push_pin_outlined
                      : Icons.push_pin),
                  title: Text(c.pinnedAt != null ? '取消置顶' : '置顶'),
                ),
              ),
            ],
            child: showBadge
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _statusColor(statusEnum, context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _statusLabel(statusEnum),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  )
                : const Icon(Icons.more_vert),
          );
        }

        final tile = ListTile(
          leading: leading,
          selected: selectionMode && selected,
          dense: fieldStyle.compact,
          visualDensity: fieldStyle.compact
              ? VisualDensity.compact
              : null,
          contentPadding: fieldStyle.compact
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 2)
              : null,
          title: titleBlockContent,
          subtitle: hasSubtitle
              ? Text(
                  subtitleParts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          trailing: trailing,
        );

        return GestureDetector(
          onLongPress: () {
            if (!ref.read(selectionModeProvider)) {
              ref.read(selectionModeProvider.notifier).state = true;
              ref.read(selectedIdsProvider.notifier).state = {c.id};
              HapticFeedback.mediumImpact();
            }
          },
          onTap: () {
            final selMode = ref.read(selectionModeProvider);
            if (selMode) {
              toggleSelect();
            } else {
              context.push('/read/${c.id}');
            }
          },
          child: tile,
        );
      },
    );
  }
}

enum _TileAction { togglePin }

String _extractSnippet(String contentMd) {
  if (contentMd.isEmpty) return '';
  for (var line in contentMd.split('\n')) {
    line = line.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('![') || RegExp(r'^\[[^\]]*\]\(').hasMatch(line)) {
      continue;
    }
    var text = line
        .replaceFirst(RegExp(r'^#{1,6}\s*'), '')
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
        .replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1')
        .replaceAll('*', '')
        .replaceAll('_', '')
        .replaceAll('`', '')
        .replaceAll(RegExp(r'^>\s?'), '');
    text = text.trim();
    if (text.isEmpty) continue;
    return text.length > 80 ? '${text.substring(0, 80)}…' : text;
  }
  return '';
}

Color _statusColor(CollectionStatus? s, BuildContext context) =>
    CollectionEnums.statusColor(s);
