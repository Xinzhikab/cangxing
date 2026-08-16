import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/core/constants/category_templates.dart';
import 'package:fav_app/features/collections/data/models/category.dart';
import 'package:fav_app/features/collections/data/providers/category_repository_provider.dart';
import 'package:fav_app/features/collections/data/providers/category_tree_provider.dart';
import 'package:fav_app/features/collections/data/providers/collection_repository_provider.dart';
import 'package:fav_app/features/collections/data/providers/collections_list_controller.dart';
import 'package:fav_app/features/collections/presentation/pages/category_articles_page.dart';

/// 分类页：可在 文件夹 / 标签 / 平台 / 作者 四种分类维度间切换浏览。
class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  static const _modes = ['folder', 'tag', 'platform', 'author'];
  String get _mode => _modes[_tabCtrl.index];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _modes.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  List<String> _buildCategoryPath(List<Category> all, Category cat) {
    final byId = {for (final c in all) c.id: c};
    final temp = <String>[cat.name];
    String? pid = cat.parentId;
    while (pid != null && byId.containsKey(pid)) {
      final parent = byId[pid]!;
      temp.insert(0, parent.name);
      pid = parent.parentId;
    }
    return temp;
  }

  void _createDialog(
    BuildContext ctx,
    WidgetRef ref, {
    Category? parent,
  }) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: Text(parent == null
            ? '新建文件夹'
            : '在「${parent.name}」下新建子文件夹'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名称'),
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
              final siblings = await repo.childrenOf(parent?.id);
              await repo.create(Category(
                id: const Uuid().v4(),
                name: nameCtrl.text.trim(),
                parentId: parent?.id,
                sortOrder: siblings.length,
                createdAt: DateTime.now(),
              ));
              ref.invalidate(categoriesListProvider);
              ref.invalidate(collectionsListProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _renameDialog(BuildContext ctx, WidgetRef ref, Category cat) {
    final nameCtrl = TextEditingController(text: cat.name);
    showDialog(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名文件夹'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名称'),
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
              await repo.update(cat.copyWith(name: nameCtrl.text.trim()));
              ref.invalidate(categoriesListProvider);
              ref.invalidate(collectionsListProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteDialog(
    BuildContext ctx,
    WidgetRef ref, {
    required Category cat,
  }) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('会级联删除子目录，其中的收藏将回退到「未分类」。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(categoryRepositoryProvider);
    // 确认框退出动画期间 Navigator 锁定，等它结束再开进度弹窗
    await Future.delayed(const Duration(milliseconds: 300));
    if (!ctx.mounted) return;
    BuildContext? dialogCtx;
    showDialog(
      context: ctx,
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
                Text('正在删除「${cat.name}」...'),
              ],
            ),
          ),
        );
      },
    );
    try {
      await repo.delete(cat.id);
    } finally {
      await Future.delayed(const Duration(milliseconds: 150));
      if (dialogCtx != null && dialogCtx!.mounted) {
        Navigator.of(dialogCtx!).pop();
      }
    }
    ref.invalidate(categoriesListProvider);
    ref.invalidate(collectionsListProvider);
    // 不要 pop 页面：分类页是 shell 分支根路由，弹出会导致黑屏
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('已删除「${cat.name}」及其子目录')),
      );
    }
  }

  void _openArticles(BuildContext context, CategoryArticlesArgs args) {
    context.push('/categories/articles', extra: args);
  }

  /// 导入推荐文件夹模板：勾选导入，已存在的同名顶层文件夹自动跳过
  Future<void> _importTemplateDialog(BuildContext ctx, WidgetRef ref) async {
    final selected = {...kCategoryTemplate.keys};
    final existingNames = (await ref
            .read(categoryRepositoryProvider)
            .listAll())
        .where((c) => c.parentId == null)
        .map((c) => c.name)
        .toSet();
    if (!ctx.mounted) return;
    await showDialog<void>(
      context: ctx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('导入推荐文件夹'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in kCategoryTemplate.entries)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        existingNames.contains(e.key)
                            ? '${e.key}（已存在，跳过）'
                            : e.key,
                      ),
                      subtitle: Text(e.value),
                      value: selected.contains(e.key),
                      onChanged: existingNames.contains(e.key)
                          ? null
                          : (v) => setDialog(() => v ?? false
                              ? selected.add(e.key)
                              : selected.remove(e.key)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final created = await importCategoryTemplate(
                  ref.read(categoryRepositoryProvider),
                  selected,
                );
                ref.invalidate(categoriesListProvider);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('已导入 $created 个文件夹')),
                  );
                }
              },
              child: const Text('导入'),
            ),
          ],
        ),
      ),
    );
  }

  void _createTagDialog(BuildContext ctx, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text('新建标签'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '标签名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final repo = ref.read(collectionRepositoryProvider);
              await repo.addTag(nameCtrl.text.trim());
              ref.invalidate(allTagsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _renameTagDialog(BuildContext ctx, WidgetRef ref, String name) {
    final nameCtrl = TextEditingController(text: name);
    showDialog(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名标签'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '新标签名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final repo = ref.read(collectionRepositoryProvider);
              await repo.renameTag(name, nameCtrl.text.trim());
              ref.invalidate(allTagsProvider);
              ref.invalidate(collectionsListProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteTag(
    BuildContext ctx,
    WidgetRef ref,
    String name,
  ) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('删除「$name」会同时从所有收藏中移除该标签。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(collectionRepositoryProvider);
    await repo.deleteTag(name);
    ref.invalidate(allTagsProvider);
    ref.invalidate(collectionsListProvider);
  }

  void _showTagActions(BuildContext ctx, WidgetRef ref, String name) {
    showModalBottomSheet<void>(
      context: ctx,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _renameTagDialog(ctx, ref, name);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red.shade700),
              title: Text('删除', style: TextStyle(color: Colors.red.shade700)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _confirmDeleteTag(ctx, ref, name);
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _platformLabel(String k) =>
      CollectionEnums.platformLabel(CollectionEnums.platformFromSql(k));

  Widget _buildFolderBody(WidgetRef ref) {
    final catsAsync = ref.watch(categoriesListProvider);
    return catsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('错误: $e')),
      data: (list) {
        if (list.isEmpty) {
          return const Center(child: Text('暂无文件夹，点右上角 + 新建'));
        }
        final rows = buildTreeView(list);
        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final item = rows[i];
            return ListTile(
              contentPadding: EdgeInsets.only(
                left: 16 + item.level * 24.0,
                right: 8,
              ),
              leading: const Icon(Icons.folder, color: Colors.amber),
              title: Text(item.cat.name),
              trailing: PopupMenuButton<String>(
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'rename',
                    child: ListTile(
                      leading: Icon(Icons.edit),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('重命名'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'add_child',
                    child: ListTile(
                      leading: Icon(Icons.create_new_folder),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('新建子文件夹'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: Colors.red),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('删除', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                ],
                onSelected: (v) {
                  switch (v) {
                    case 'rename':
                      _renameDialog(context, ref, item.cat);
                      break;
                    case 'add_child':
                      _createDialog(context, ref, parent: item.cat);
                      break;
                    case 'delete':
                      _confirmDeleteDialog(context, ref, cat: item.cat);
                      break;
                  }
                },
              ),
              onTap: () => _openArticles(
                context,
                CategoryArticlesArgs(
                  categoryPath: _buildCategoryPath(list, item.cat),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTagBody(WidgetRef ref) {
    final tagsAsync = ref.watch(allTagsProvider);
    return tagsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('错误: $e')),
      data: (counts) {
        final entries = counts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        if (entries.isEmpty) {
          return const Center(child: Text('暂无标签'));
        }
        return ListView.builder(
          itemCount: entries.length,
          itemBuilder: (_, i) {
            final e = entries[i];
            return ListTile(
              leading: const Icon(Icons.tag, color: Colors.blue),
              title: Text(e.key),
              subtitle: Text('${e.value} 篇'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openArticles(
                context,
                CategoryArticlesArgs(tag: e.key),
              ),
              onLongPress: () => _showTagActions(context, ref, e.key),
            );
          },
        );
      },
    );
  }

  Widget _buildPlatformBody(WidgetRef ref) {
    final stats = ref.watch(groupStatsProvider);
    return stats.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('错误: $e')),
      data: (groups) {
        final platforms = groups['platforms'] ?? const [];
        if (platforms.isEmpty) {
          return const Center(child: Text('暂无收藏'));
        }
        return ListView.builder(
          itemCount: platforms.length,
          itemBuilder: (_, i) {
            final m = platforms[i];
            final key = m.keys.first;
            final cnt = m.values.first;
            final platformEnum = CollectionEnums.platformFromSql(key);
            return ListTile(
              leading: Icon(CollectionEnums.platformIcon(platformEnum),
                  color: Colors.indigo),
              title: Text(_platformLabel(key)),
              subtitle: Text('$cnt 篇'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openArticles(
                context,
                CategoryArticlesArgs(platform: key),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAuthorBody(WidgetRef ref) {
    final stats = ref.watch(groupStatsProvider);
    return stats.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('错误: $e')),
      data: (groups) {
        final authors = groups['authors'] ?? const [];
        if (authors.isEmpty) {
          return const Center(child: Text('暂无作者'));
        }
        return ListView.builder(
          itemCount: authors.length,
          itemBuilder: (_, i) {
            final m = authors[i];
            final key = m.keys.first;
            final cnt = m.values.first;
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(key.isEmpty ? '佚名' : key),
              subtitle: Text('$cnt 篇'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openArticles(
                context,
                CategoryArticlesArgs(author: key),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _tabCtrl,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('分类'),
            actions: [
              if (_mode == 'folder') ...[
                IconButton(
                  icon: const Icon(Icons.auto_awesome_outlined),
                  tooltip: '导入推荐模板',
                  onPressed: () => _importTemplateDialog(context, ref),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: '新建文件夹',
                  onPressed: () => _createDialog(context, ref),
                ),
              ],
              if (_mode == 'tag')
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: '新建标签',
                  onPressed: () => _createTagDialog(context, ref),
                ),
            ],
          ),
          body: Column(
            children: [
              TabBar(
                controller: _tabCtrl,
                tabs: const [
                  Tab(icon: Icon(Icons.folder), text: '收藏'),
                  Tab(icon: Icon(Icons.tag), text: '标签'),
                  Tab(icon: Icon(Icons.public), text: '平台'),
                  Tab(icon: Icon(Icons.person), text: '作者'),
                ],
              ),
              Expanded(
                // TabBarView：左右滑动切换分类维度
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    Consumer(builder: (_, ref, __) => _buildFolderBody(ref)),
                    Consumer(builder: (_, ref, __) => _buildTagBody(ref)),
                    Consumer(builder: (_, ref, __) => _buildPlatformBody(ref)),
                    Consumer(builder: (_, ref, __) => _buildAuthorBody(ref)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
