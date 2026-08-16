import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:fav_app/features/collections/data/models/category.dart';
import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/collections/data/providers/category_tree_provider.dart';
import 'package:fav_app/features/collections/data/providers/category_repository_provider.dart';
import 'package:fav_app/features/collections/data/providers/collections_list_controller.dart';
import 'package:fav_app/features/collections/data/providers/collection_repository_provider.dart';
import 'package:fav_app/features/settings/data/providers/list_field_style_provider.dart';

/// 长按进入的批量选择模式
final selectionModeProvider = StateProvider<bool>((ref) => false);
final selectedIdsProvider = StateProvider<Set<String>>((ref) => {});

class CollectionsPage extends ConsumerStatefulWidget {
  const CollectionsPage({super.key});

  @override
  ConsumerState<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends ConsumerState<CollectionsPage> {
  late final TextEditingController _searchCtrl;
  /// 搜索输入框是否展开。默认只显示「假搜索栏」，点按才展开真实
  /// 输入框，避免抽屉关闭等场景焦点/点击穿透导致键盘意外弹出。
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectionMode = ref.watch(selectionModeProvider);
    return Scaffold(
      appBar: selectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(),
      drawer: selectionMode ? null : const _CategoryDrawer(),
      body: Column(
        children: [
          if (!selectionMode) const _FilterChipRow(),
          Expanded(child: _ListBody()),
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

  AppBar _buildNormalAppBar() {
    final scheme = Theme.of(context).colorScheme;
    if (_searchOpen) {
      // 展开态：真实输入框 + 关闭按钮；关闭时清空过滤并收起键盘
      return AppBar(
        title: TextField(
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
          ),
          onChanged: (v) => ref
              .read(collectionsFilterProvider.notifier)
              .update((s) => s.copyWith(keyword: v)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: '关闭搜索',
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              _searchCtrl.clear();
              ref
                  .read(collectionsFilterProvider.notifier)
                  .update((s) => s.copyWith(keyword: ''));
              setState(() => _searchOpen = false);
            },
          ),
        ],
      );
    }
    // 收起态：假搜索栏（纯展示，不持有焦点），点按才展开
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
        // 卡片样式设置已移到「设置 → 主题与外观 → 首页卡片样式」
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

  /// 批量选择模式的 AppBar：计数 + 全选 + 批量移动/删除
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
          icon: const Icon(Icons.drive_file_move_outline),
          tooltip: '移动到分类',
          onPressed: selected.isEmpty ? null : () => _batchMove(exitSelection),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: '删除',
          onPressed: selected.isEmpty ? null : () => _batchDelete(exitSelection),
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
        content: const Text('对应的正文与图片文件会一并删除，不可恢复。'),
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
      } catch (_) {}
    }
    ref.invalidate(collectionsListProvider);
    ref.invalidate(groupStatsProvider);
    ref.invalidate(allTagsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 ${ids.length} 篇收藏')),
      );
    }
    onDone();
  }

  Future<void> _batchMove(VoidCallback onDone) async {
    final ids = ref.read(selectedIdsProvider);
    final allCategories = ref.read(categoriesListProvider).valueOrNull ?? [];
    final byId = {for (final c in allCategories) c.id: c};

    // 构建所有分类的完整路径
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
      } catch (_) {}
    }
    ref.invalidate(collectionsListProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已移动 $moved 篇到 ${picked.join('/')}')),
      );
    }
    onDone();
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
        ref
            .read(collectionsFilterProvider.notifier)
            .update((s) => s.copyWith(categoryPath: path));
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
                  ref
                      .read(collectionsFilterProvider.notifier)
                      .update((s) => s.copyWith(categoryPath: null));
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
            // 等 bottom sheet 退出动画结束（Navigator 锁定期间
            // push 进度弹窗会抛断言），再执行删除
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
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: FilterChip(
                        label: Text('${_statusLabel(k)} $cnt'),
                        selected: filter.status == k,
                        onSelected: (_) => _updFilter(
                          ref,
                          filter.copyWith(status: k),
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
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: FilterChip(
                        label: Text('${_platformLabel(k)} $cnt'),
                        selected: filter.platform == k,
                        onSelected: (_) => _updFilter(
                          ref,
                          filter.copyWith(platform: k),
                        ),
                      ),
                    );
                  }).toList(growable: false) ??
                  [],
              const SizedBox(width: 12),
              PopupMenuButton<String>(
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'collected_at',
                    child: Text('按收藏时间'),
                  ),
                  const PopupMenuItem(
                    value: 'published_at',
                    child: Text('按原帖时间'),
                  ),
                  const PopupMenuItem(
                    value: 'title',
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
            ],
          );
        },
      ),
    );
  }
}

void _updFilter(WidgetRef ref, CollectionsFilter f) =>
    ref.read(collectionsFilterProvider.notifier).state = f;

String _statusLabel(String k) =>
    {'learning': '想学', 'done': '已完成'}[k] ?? k;

String _platformLabel(String k) =>
    {'douyin': '抖音', 'xiaoheihe': '小黑盒', 'coolapk': '酷安', 'other': '其他'}[
        k] ??
    k;

String _sortLabel(String k) =>
    {'collected_at': '收藏时间', 'published_at': '原帖时间', 'title': '标题'}[
        k] ??
    k;

class _ListBody extends StatelessWidget {
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
        // 栏目显示配置：图标/平台/作者/时间可自定义组合
        final fieldStyle = ref.watch(listFieldStyleProvider);

        void toggleSelect() {
          final ids = Set<String>.from(ref.read(selectedIdsProvider));
          selected ? ids.remove(c.id) : ids.add(c.id);
          ref.read(selectedIdsProvider.notifier).state = ids;
        }

        // 副标题按开关拼接：平台 · 作者 · 时间 · 分类
        final subtitleParts = <String>[
          if (fieldStyle.showPlatform) _platformLabel(c.sourcePlatform),
          if (fieldStyle.showAuthor)
            c.author.isEmpty ? '佚名' : c.author,
          if (fieldStyle.showTime)
            DateFormat('yyyy-MM-dd HH:mm').format(c.collectedAt),
          if (fieldStyle.showCategory && c.category.isNotEmpty)
            c.category.join('/'),
        ];
        final hasSubtitle = subtitleParts.isNotEmpty;

        // 正文摘要：Markdown 里第一段非空纯文本，截 80 字
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
            child: Text(_platformLabel(c.sourcePlatform)[0]),
          );
        }

        final showBadge = !selectionMode &&
            fieldStyle.showStatusBadge &&
            (c.status == 'learning' || c.status == 'done');

        // 标题 + 摘要 + 标签都在 title 区纵向排布
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              c.title,
              maxLines: fieldStyle.titleLines,
              overflow: TextOverflow.ellipsis,
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

        return ListTile(
          onTap: selectionMode ? toggleSelect : () => context.push('/read/${c.id}'),
          // 长按进入批量选择模式（单项编辑/删除入口在详情页）
          onLongPress: () {
            ref.read(selectionModeProvider.notifier).state = true;
            ref.read(selectedIdsProvider.notifier).state = {c.id};
          },
          leading: leading,
          selected: selectionMode && selected,
          dense: fieldStyle.compact,
          visualDensity: fieldStyle.compact
              ? VisualDensity.compact
              : null,
          contentPadding: fieldStyle.compact
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 2)
              : null,
          title: titleBlock,
          subtitle: hasSubtitle
              ? Text(
                  subtitleParts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          // 已读/未读功能已移除：仅「想学 / 已完成」显示状态徽标
          trailing: selectionMode
              ? null
              : showBadge
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColor(c.status, context),
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
  }
}

/// 从 Markdown 正文提取摘要：第一段非空纯文本，
/// 去掉常见 Markdown 标记（标题符/图片/链接/加粗），截 80 字。
String _extractSnippet(String contentMd) {
  if (contentMd.isEmpty) return '';
  for (var line in contentMd.split('\n')) {
    line = line.trim();
    if (line.isEmpty) continue;
    // 跳过图片与链接行
    if (line.startsWith('![') || RegExp(r'^\[[^\]]*\]\(').hasMatch(line)) {
      continue;
    }
    var text = line
        .replaceFirst(RegExp(r'^#{1,6}\s*'), '') // 标题符
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '') // 行内图片
        .replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1') // 链接取文字
        .replaceAll('*', '')
        .replaceAll('_', '')
        .replaceAll('`', '')
        .replaceAll(RegExp(r'^>\s?'), ''); // 引用符
    text = text.trim();
    if (text.isEmpty) continue;
    return text.length > 80 ? '${text.substring(0, 80)}…' : text;
  }
  return '';
}

Color _statusColor(String s, BuildContext context) {
  switch (s) {
    case 'learning':
      return Colors.orange;
    case 'done':
      return Colors.green;
    default:
      return Colors.grey;
  }
}
