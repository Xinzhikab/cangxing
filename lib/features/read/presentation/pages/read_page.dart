import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/features/collections/data/models/category.dart';
import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/collections/data/models/collection_note.dart';
import 'package:fav_app/features/collections/data/providers/category_tree_provider.dart';
import 'package:fav_app/features/collections/data/providers/collection_detail_provider.dart';
import 'package:fav_app/features/collections/data/providers/collection_repository_provider.dart';
import 'package:fav_app/features/collections/data/providers/collections_list_controller.dart';
import 'package:fav_app/features/collections/presentation/pages/category_articles_page.dart';
import 'package:fav_app/features/collections/presentation/widgets/meta_edit_dialog.dart';
import 'package:fav_app/features/settings/data/providers/reading_style_provider.dart';

class ReadPage extends ConsumerStatefulWidget {
  final String id;
  final bool fromLearning;

  const ReadPage({
    super.key,
    required this.id,
    this.fromLearning = false,
  });

  @override
  ConsumerState<ReadPage> createState() => _ReadPageState();
}

class _ReadPageState extends ConsumerState<ReadPage> {
  late final TextEditingController _noteCtrl;
  late final FocusNode _noteFocus;
  late final TextEditingController _searchCtrl;
  late final FocusNode _searchFocus;
  final PageController _pageCtrl = PageController();
  final ScrollController _bodyScrollCtrl = ScrollController();
  Collection? _col;
  Timer? _saveScrollTimer;
  bool _searchOpen = false;
  int _hitCount = 0;
  int _currentHit = 0;
  String _searchKw = '';

  @override
  void initState() {
    super.initState();
    _noteCtrl = TextEditingController();
    _noteFocus = FocusNode();
    _searchCtrl = TextEditingController();
    _searchFocus = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final col = await ref.read(collectionDetailProvider(widget.id).future);
      if (col != null) {
        _col = col;
      }
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble('read_scroll_${widget.id}');
      if (saved != null && saved > 0 && _bodyScrollCtrl.hasClients) {
        _bodyScrollCtrl.jumpTo(saved.clamp(0.0, _bodyScrollCtrl.position.maxScrollExtent));
      }
      _bodyScrollCtrl.addListener(() {
        _saveScrollTimer?.cancel();
        _saveScrollTimer = Timer(const Duration(milliseconds: 500), () async {
          final p = await SharedPreferences.getInstance();
          await p.setDouble('read_scroll_${widget.id}', _bodyScrollCtrl.offset);
        });
      });
    });
  }

  @override
  void dispose() {
    _saveScrollTimer?.cancel();
    _bodyScrollCtrl.dispose();
    _noteCtrl.dispose();
    _noteFocus.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _applySearch(String kw) {
    setState(() {
      _searchKw = kw.trim();
      if (_searchKw.isEmpty) {
        _hitCount = 0;
        _currentHit = 0;
      } else {
        final rawMd = _col?.contentMd.isEmpty ?? true
            ? _col?.rawInput ?? ''
            : _col?.contentMd ?? '';
        final esc = RegExp.escape(_searchKw);
        final re = RegExp(esc, caseSensitive: false);
        _hitCount = re.allMatches(rawMd).length;
        _currentHit = _hitCount > 0 && _currentHit == 0 ? 1 : _currentHit;
        if (_currentHit > _hitCount) _currentHit = _hitCount;
      }
    });
  }

  void _rebuildHighlight() {
    setState(() {});
  }

  String _platformLabel(String k) =>
      CollectionEnums.platformLabel(CollectionEnums.platformFromSql(k));

  /// 排版设置面板（效仿「阅读」App）：字号/行距/页边距实时调节，自动持久化
  void _showReadingStyleSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final style = ref.watch(readingStyleProvider);
          final notifier = ref.read(readingStyleProvider.notifier);
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('排版设置',
                        style: Theme.of(ctx).textTheme.titleMedium),
                    TextButton.icon(
                      onPressed: () => notifier.reset(),
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('重置'),
                    ),
                  ],
                ),
                Text('字号 ${style.fontSize.toStringAsFixed(0)}',
                    style: Theme.of(ctx).textTheme.bodyMedium),
                Slider(
                  value: style.fontSize,
                  min: 12,
                  max: 28,
                  divisions: 16,
                  label: style.fontSize.toStringAsFixed(0),
                  onChanged: (v) => notifier.update(fontSize: v),
                ),
                Text('行距 ${style.lineHeight.toStringAsFixed(1)}',
                    style: Theme.of(ctx).textTheme.bodyMedium),
                Slider(
                  value: style.lineHeight,
                  min: 1.2,
                  max: 2.4,
                  divisions: 12,
                  label: style.lineHeight.toStringAsFixed(1),
                  onChanged: (v) => notifier.update(lineHeight: v),
                ),
                Text('页边距 ${style.pagePadding.toStringAsFixed(0)}',
                    style: Theme.of(ctx).textTheme.bodyMedium),
                Slider(
                  value: style.pagePadding,
                  min: 8,
                  max: 32,
                  divisions: 12,
                  label: style.pagePadding.toStringAsFixed(0),
                  onChanged: (v) => notifier.update(pagePadding: v),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '设置即时生效并自动保存',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _statusLabel(String k) =>
      CollectionEnums.statusLabel(CollectionEnums.statusFromSql(k));

  Color _statusColor(String s, BuildContext context) =>
      CollectionEnums.statusColor(CollectionEnums.statusFromSql(s));

  /// 提交一条新笔记（评论区模式，可无限追加）。
  Future<void> _submitNote() async {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty || _col == null) return;
    try {
      await ref.read(collectionRepositoryProvider).addNote(
            CollectionNote(
              id: const Uuid().v4(),
              collectionId: widget.id,
              content: text,
              createdAt: DateTime.now(),
            ),
          );
      _noteCtrl.clear();
      _noteFocus.unfocus();
      ref.invalidate(collectionNotesProvider(widget.id));
      ref.invalidate(collectionDetailProvider(widget.id));
      ref.invalidate(collectionsListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('笔记已保存 ✓'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败：$e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _deleteNote(CollectionNote note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条笔记？'),
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
    try {
      await ref.read(collectionRepositoryProvider).deleteNote(note.id);
      ref.invalidate(collectionNotesProvider(widget.id));
      ref.invalidate(collectionDetailProvider(widget.id));
      ref.invalidate(collectionsListProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除笔记失败：$e')),
        );
      }
    }
  }

  /// 切换到全屏评论区（PageView 自带左滑进入、右滑返回文章）。
  void _goToComments() {
    if (_pageCtrl.hasClients) {
      _pageCtrl.animateToPage(
        1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _showLearningDialog(Collection col, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('标记为「想学」并安排回顾'),
        content: Wrap(
          children: [1, 3, 7, 14, 30]
              .map(
                (d) => Padding(
                  padding: const EdgeInsets.all(4),
                  child: FilledButton(
                    onPressed: () async {
                      final due = DateTime.now().add(Duration(days: d));
                      await ref.read(collectionRepositoryProvider).update(
                            col.copyWith(
                              status: CollectionEnums.statusToSql(
                                  CollectionStatus.learning)!,
                              reviewDueAt: due,
                            ),
                          );
                      ref.invalidate(collectionDetailProvider(widget.id));
                      ref.invalidate(collectionsListProvider);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('已安排 ${d} 天后回顾')),
                        );
                      }
                    },
                    child: Text('$d 天'),
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }

  void _showDoneDialog(Collection col, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('标记为「已完成」？'),
        content: const Text('完成后将清除阅读进度记忆。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await ref.read(collectionRepositoryProvider).update(
                    col.copyWith(
                      status: CollectionEnums.statusToSql(
                          CollectionStatus.done)!,
                    ),
                  );
              ref.invalidate(collectionDetailProvider(widget.id));
              ref.invalidate(collectionsListProvider);
              SharedPreferences.getInstance()
                  .then((p) => p.remove('read_scroll_${widget.id}'));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text('已标记为完成 ✓'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('确认完成'),
          ),
        ],
      ),
    );
  }

  String _stripMarkdown(String md) {
    var text = md;
    text = text.replaceAllMapped(
      RegExp(r'^(#+)\s+', multiLine: true),
      (m) => '',
    );
    text = text.replaceAllMapped(
      RegExp(r'\*\*(.+?)\*\*'),
      (m) => m.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'\*(.+?)\*'),
      (m) => m.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'\[(.+?)\]\(.+?\)'),
      (m) => m.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'^>\s+', multiLine: true),
      (m) => '',
    );
    text = text.replaceAll('  \n', '\n');
    return text.trim();
  }

  void _showShareSheet(Collection col) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('导出正文为 Markdown'),
                subtitle: const Text('复制到剪贴板，可粘贴分享'),
                onTap: () async {
                  final md = col.contentMd.isEmpty ? col.rawInput : col.contentMd;
                  final text = '$md\n\n--- 来源：${col.sourceUrl}（藏星 cn.cangxing.mobile）';
                  await Clipboard.setData(ClipboardData(text: text));
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制 Markdown 到剪贴板，可粘贴分享'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.text_snippet_outlined),
                title: const Text('导出纯文本'),
                subtitle: const Text('去除格式后复制到剪贴板'),
                onTap: () async {
                  final md = col.contentMd.isEmpty ? col.rawInput : col.contentMd;
                  final plain = _stripMarkdown(md);
                  final text = '$plain\n\n--- 来源：${col.sourceUrl}（藏星 cn.cangxing.mobile）';
                  await Clipboard.setData(ClipboardData(text: text));
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制纯文本到剪贴板'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showTagsDialog(Collection c) async {
    final tagCtrl = TextEditingController();
    final tags = List<String>.from(c.tags);
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('修改标签'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tags.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in tags)
                        InputChip(
                          label: Text(t),
                          onDeleted: () =>
                              setDialogState(() => tags.remove(t)),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: tagCtrl,
                        decoration: const InputDecoration(
                          hintText: '输入新标签',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) {
                          final t = tagCtrl.text.trim();
                          if (t.isNotEmpty && !tags.contains(t)) {
                            setDialogState(() {
                              tags.add(t);
                              tagCtrl.clear();
                            });
                          }
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        final t = tagCtrl.text.trim();
                        if (t.isNotEmpty && !tags.contains(t)) {
                          setDialogState(() {
                            tags.add(t);
                            tagCtrl.clear();
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ref.watch(allTagsProvider).maybeWhen(
                      data: (counts) {
                        final candidates = counts.keys
                            .where((t) => !tags.contains(t))
                            .toList()
                          ..sort((a, b) =>
                              (counts[b] ?? 0).compareTo(counts[a] ?? 0));
                        if (candidates.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '已有标签（点击添加）',
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final t in candidates.take(20))
                                  ActionChip(
                                    label: Text(counts[t]! > 0
                                        ? '$t (${counts[t]})'
                                        : t),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => setDialogState(() {
                                      if (!tags.contains(t)) tags.add(t);
                                    }),
                                  ),
                              ],
                            ),
                          ],
                        );
                      },
                      orElse: () => const SizedBox.shrink(),
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
              onPressed: () => Navigator.pop(ctx, List<String>.from(tags)),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    tagCtrl.dispose();
    if (result != null) {
      await ref.read(collectionRepositoryProvider).update(
            c.copyWith(tags: result),
          );
      ref.invalidate(collectionDetailProvider(widget.id));
      ref.invalidate(collectionsListProvider);
      ref.invalidate(allTagsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('标签已更新'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  List<String> _buildPathForCategory(
    Category cat,
    Map<String, Category> byId,
  ) {
    final temp = <String>[cat.name];
    String? pid = cat.parentId;
    while (pid != null && byId.containsKey(pid)) {
      final p = byId[pid]!;
      temp.insert(0, p.name);
      pid = p.parentId;
    }
    return temp;
  }

  void _buildPathTiles(
    CategoryNode node,
    Map<String, Category> byId,
    List<Widget> tiles, {
    required int depth,
  }) {
    final path = _buildPathForCategory(node.category, byId);
    tiles.add(
      ListTile(
        title: Padding(
          padding: EdgeInsets.only(left: depth * 16.0),
          child: Text(path.join('/')),
        ),
        onTap: () => Navigator.of(context).pop(path),
      ),
    );
    for (final child in node.children) {
      _buildPathTiles(child, byId, tiles, depth: depth + 1);
    }
  }

  Future<void> _openCategoryDialog(Collection c) async {
    // 等分类列表加载完成再弹窗：valueOrNull 在未加载时为 null，
    // 会导致弹窗只显示硬编码的「未分类」
    List<Category> allCategories;
    try {
      allCategories = await ref.read(categoriesListProvider.future);
    } catch (_) {
      allCategories = const [];
    }
    if (!mounted) return;
    final byId = {for (final cc in allCategories) cc.id: cc};
    final tree = ref.read(categoryTreeProvider);

    final selected = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择分类'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...tree.when(
                  data: (roots) {
                    final tiles = <Widget>[];
                    for (final node in roots) {
                      // 表里也有「未分类」，跳过避免与底部兜底项重复
                      if (node.category.name == AppConstants.defaultCategoryName) {
                        continue;
                      }
                      _buildPathTiles(node, byId, tiles, depth: 0);
                    }
                    return tiles;
                  },
                  loading: () => [const SizedBox.shrink()],
                  error: (_, __) => [const SizedBox.shrink()],
                ),
                // 「未分类」作为兜底放最后，不再排在文件夹前面
                const Divider(height: 1),
                ListTile(
                  title: Text(AppConstants.defaultCategoryName),
                  onTap: () => Navigator.of(ctx)
                      .pop([AppConstants.defaultCategoryName]),
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
        ],
      ),
    );

    if (selected != null) {
      await ref
          .read(collectionRepositoryProvider)
          .update(c.copyWith(category: selected));
      ref.invalidate(collectionDetailProvider(widget.id));
      ref.invalidate(collectionsListProvider);
      ref.invalidate(groupStatsProvider);
      // 分类浏览页的文章列表是独立 family provider，
      // 必须 invalidate 整个 family，否则文件夹列表不刷新
      ref.invalidate(categoryArticlesProvider);
    }
  }

  Future<void> _confirmDelete() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除收藏？'),
        content: const Text('元数据、正文、图片都会删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await ref.read(collectionRepositoryProvider).delete(widget.id);
                ref.invalidate(collectionsListProvider);
                ref.invalidate(groupStatsProvider);
                // 标签计数随收藏变化，一并刷新，避免删除后标签列表
                // 显示旧数量、点进去却找不到文章
                ref.invalidate(allTagsProvider);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) context.go('/collections');
              } catch (e) {
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('删除失败：$e')),
                  );
                }
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      // 退出文章后自动刷新首页列表
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          ref.invalidate(collectionsListProvider);
          ref.invalidate(groupStatsProvider);
          ref.invalidate(categoryArticlesProvider);
        }
      },
      child: Scaffold(
      appBar: _searchOpen
          ? AppBar(
              title: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '在正文内查找',
                  border: InputBorder.none,
                ),
                onChanged: _applySearch,
              ),
              actions: [
                if (_hitCount > 0)
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    tooltip: '上一个',
                    onPressed: () {
                      setState(() {
                        _currentHit =
                            _currentHit <= 1 ? _hitCount : _currentHit - 1;
                      });
                      _rebuildHighlight();
                    },
                  ),
                if (_hitCount > 0)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
                    child: Text(
                      _hitCount > 0 ? '$_currentHit/$_hitCount' : '',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                if (_hitCount > 0)
                  IconButton(
                    icon: const Icon(Icons.arrow_downward),
                    tooltip: '下一个',
                    onPressed: () {
                      setState(() {
                        _currentHit =
                            _currentHit >= _hitCount ? 1 : _currentHit + 1;
                      });
                      _rebuildHighlight();
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '关闭查找',
                  onPressed: () {
                    setState(() {
                      _searchOpen = false;
                      _searchCtrl.clear();
                    });
                    _applySearch('');
                  },
                ),
              ],
            )
          : AppBar(
        title: Consumer(
          builder: (_, ref, __) {
            final async = ref.watch(collectionDetailProvider(widget.id));
            return async.maybeWhen(
              data: (col) {
                if (col == null) {
                  return const Text('详情');
                }
                final catStr = col.category.isEmpty
                    ? AppConstants.defaultCategoryName
                    : col.category.join('/');
                final tagStr = col.tags.isEmpty
                    ? ''
                    : '  #${col.tags.join(' #')}';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      col.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    InkWell(
                      onTap: () async {
                        final ok = await showMetaEditDialog(
                          context,
                          ref,
                          widget.id,
                        );
                        if (ok) {
                          ref.invalidate(collectionDetailProvider(widget.id));
                          ref.invalidate(collectionsListProvider);
                        }
                        if (!mounted) return;
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            content: Text(ok ? '收藏信息已更新' : '未修改'),
                          ),
                        );
                      },
                      child: Text(
                        '📁 $catStr$tagStr',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                );
              },
              orElse: () => const Text('详情'),
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '在正文内查找',
            onPressed: () {
              setState(() {
                _searchOpen = true;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                FocusScope.of(context).requestFocus(_searchFocus);
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.format_size),
            tooltip: '排版设置',
            onPressed: () => _showReadingStyleSheet(),
          ),
          Consumer(
            builder: (_, ref, __) {
              final async = ref.watch(collectionDetailProvider(widget.id));
              return async.maybeWhen(
                data: (col) {
                  if (col == null) {
                    return const SizedBox.shrink();
                  }
                  return Row(
                    children: [
                      IconButton(
                        icon: Icon(col.pinnedAt != null
                            ? Icons.push_pin
                            : Icons.push_pin_outlined),
                        tooltip: col.pinnedAt != null ? '取消置顶' : '置顶',
                        onPressed: () async {
                          await ref
                              .read(collectionRepositoryProvider)
                              .togglePin(widget.id);
                          ref.invalidate(collectionDetailProvider(widget.id));
                          ref.invalidate(collectionsListProvider);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(col.pinnedAt != null
                                    ? '已取消置顶'
                                    : '已置顶'),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.ios_share),
                        tooltip: '分享',
                        onPressed: () => _showShareSheet(col),
                      ),
                      IconButton(
                        icon: const Icon(Icons.local_offer_outlined),
                        tooltip: '标签',
                        onPressed: () => _showTagsDialog(col),
                      ),
                      IconButton(
                        icon: const Icon(Icons.folder_outlined),
                        tooltip: '分类',
                        onPressed: () => _openCategoryDialog(col),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: '编辑元信息',
                        onPressed: () async {
                          final ok = await showMetaEditDialog(
                            context,
                            ref,
                            widget.id,
                          );
                          if (ok) {
                            ref.invalidate(collectionDetailProvider(widget.id));
                            ref.invalidate(collectionsListProvider);
                          }
                          if (!mounted) return;
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(ok ? '收藏信息已更新' : '未修改'),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error),
                        tooltip: '删除收藏',
                        onPressed: _confirmDelete,
                      ),
                      if (col.sourceUrl.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.open_in_new),
                          tooltip: '原帖',
                          onPressed: () async {
                            await launchUrl(
                              Uri.parse(col.sourceUrl),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                        ),
                    ],
                  );
                },
                orElse: () => const SizedBox.shrink(),
              );
            },
          ),
        ],
      ),
      body: ref.watch(collectionDetailProvider(widget.id)).when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('加载失败')),
        data: (col) {
          _col = col;
          if (col == null) {
            return const Center(child: Text('找不到该收藏'));
          }
          // 已读/未读功能已移除：仅「想学 / 已完成」状态显示徽标
          final statusEnum = CollectionEnums.statusFromSql(col.status);
          final hasStatusChip = statusEnum == CollectionStatus.learning ||
              statusEnum == CollectionStatus.done;
          final rootDirAsync = ref.watch(storageDirRootProvider);
          return PageView(
            controller: _pageCtrl,
            children: [
              // 视图 0：文章正文（默认，右滑不越界；左滑进入评论区）
              ListView(
                controller: _bodyScrollCtrl,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  Padding(
                    padding: EdgeInsets.all(
                      ref.watch(readingStyleProvider).pagePadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标题已在 AppBar 展示；平台/作者/标签 chip 可点，
                        // 直接进入同维度的关联收藏列表
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            ActionChip(
                              avatar: const Icon(Icons.public_outlined, size: 16),
                              label: Text(_platformLabel(col.sourcePlatform)),
                              onPressed: () => context.push(
                                '/categories/articles',
                                extra: CategoryArticlesArgs(
                                  categoryPath: const [],
                                  platform: col.sourcePlatform,
                                ),
                              ),
                            ),
                            if (col.author.isNotEmpty)
                              ActionChip(
                                avatar: const Icon(Icons.person_outline, size: 16),
                                label: Text(col.author),
                                onPressed: () => context.push(
                                  '/categories/articles',
                                  extra: CategoryArticlesArgs(
                                    categoryPath: const [],
                                    author: col.author,
                                  ),
                                ),
                              ),
                            if (col.publishedAt != null)
                              Chip(
                                avatar: const Icon(
                                    Icons.calendar_today_outlined, size: 16),
                                label: Text(
                                    DateFormat('yyyy-MM-dd').format(col.publishedAt!)),
                              ),
                            if (hasStatusChip)
                              Chip(
                                backgroundColor:
                                    _statusColor(col.status, context),
                                labelStyle:
                                    const TextStyle(color: Colors.white),
                                label: Text(_statusLabel(col.status)),
                              ),
                            ...col.tags.map(
                              (t) => ActionChip(
                                label: Text('#$t'),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => context.push(
                                  '/categories/articles',
                                  extra: CategoryArticlesArgs(
                                    categoryPath: const [],
                                    tag: t,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  rootDirAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) =>
                        const Center(child: Text('加载失败')),
                    data: (rootDir) {
                      return Padding(
                        // 正文左右留白收紧，文字更贴近屏幕，提升阅读体验
                        padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
                        child: _ArticleBody(
                          // 换行统一按段落分隔渲染：纯文本原文的单换行、
                          // 以及旧版本保存的硬换行（行尾两空格）都转空行，
                          // 否则整篇挤成一段、排版与原文不符
                          md: (col.contentMd.isEmpty
                                  ? col.rawInput
                                  : col.contentMd)
                              .replaceAll('  \n', '\n\n')
                              .replaceAll(RegExp(r' *\r?\n *'), '\n\n'),
                          rootDir: rootDir,
                          searchKw: _searchKw,
                          currentHit: _currentHit,
                        ),
                      );
                    },
                  ),
                ],
              ),
              // 视图 1：全屏评论区（左滑进入，右滑返回文章）
              Column(
                children: [
                  Expanded(
                    child: _CommentSection(
                      collectionId: widget.id,
                      onDelete: _deleteNote,
                    ),
                  ),
                  _buildNoteInputBar(),
                ],
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SizedBox(
        height: 64,
        child: Consumer(
          builder: (_, ref, __) {
            final async = ref.watch(collectionDetailProvider(widget.id));
            final col = async.valueOrNull ?? _col;
            final statusEnum = col == null
                ? CollectionStatus.unread
                : (CollectionEnums.statusFromSql(col.status) ??
                    CollectionStatus.unread);
            final isDone = statusEnum == CollectionStatus.done;
            return NavigationBar(
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.edit_note),
                  label: '笔记',
                ),
                NavigationDestination(
                  icon: Icon(isDone ? Icons.task_alt : Icons.psychology_alt),
                  label: isDone ? '已完成' : '想学',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.folder),
                  label: '分类',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.auto_awesome),
                  label: 'AI 对话',
                ),
              ],
              onDestinationSelected: (idx) async {
                final c = _col;
                if (c == null) return;
                switch (idx) {
                  case 0:
                    _goToComments();
                    break;
                  case 1:
                    final s =
                        CollectionEnums.statusFromSql(c.status) ??
                            CollectionStatus.unread;
                    if (s == CollectionStatus.learning) {
                      _showDoneDialog(c, ref);
                    } else {
                      _showLearningDialog(c, ref);
                    }
                    break;
                  case 2:
                    _openCategoryDialog(c);
                    break;
                  case 3:
                    context.push('/read/${widget.id}/chat');
                    break;
                }
              },
            );
          },
        ),
      ),
      ),
    );
  }

  /// 评论区输入栏：固定在页面最底部，发布即保存。
  Widget _buildNoteInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _noteCtrl,
                focusNode: _noteFocus,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submitNote(),
                decoration: InputDecoration(
                  hintText: '写条评论...',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.send),
              tooltip: '发布笔记',
              onPressed: _submitNote,
            ),
          ],
        ),
      ),
    );
  }
}

/// 正文渲染：路由转场动画期间先显示轻量骨架，动画结束再构建
/// Markdown。正文是 shrinkWrap 全量构建（含图片解码），若在切换
/// 动画进行时同步构建，会把转场卡成幻灯片。
class _ArticleBody extends ConsumerStatefulWidget {
  final String md;
  final String rootDir;
  final String searchKw;
  final int currentHit;

  const _ArticleBody({
    required this.md,
    required this.rootDir,
    this.searchKw = '',
    this.currentHit = 0,
  });

  @override
  ConsumerState<_ArticleBody> createState() => _ArticleBodyState();
}

class _ArticleBodyState extends ConsumerState<_ArticleBody> {
  bool _ready = false;
  bool _listenerAttached = false;

  String _applyHighlightInBody(String content, String kw, int currentHit) {
    if (kw.trim().isEmpty) return content;
    final escaped = RegExp.escape(kw.trim());
    final regex = RegExp(escaped, caseSensitive: false);
    int index = 0;
    return content.replaceAllMapped(regex, (m) {
      index++;
      final isSel = index == currentHit;
      final tag = isSel ? '<<<HLS>>>' : '<<<HL>>>';
      final endTag = isSel ? '<<</HLS>>>' : '<<</HL>>>';
      return '$tag${m.group(0)}$endTag';
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listenerAttached) return;
    _listenerAttached = true;
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null || anim.status == AnimationStatus.completed) {
      _ready = true;
    } else {
      void listener(AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          anim.removeStatusListener(listener);
          if (mounted) setState(() => _ready = true);
        }
      }
      anim.addStatusListener(listener);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      // 转场期间的骨架占位：构建成本几乎为零
      final skColor =
          Theme.of(context).colorScheme.surfaceContainerHighest;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in const [0.9, 1.0, 0.75, 0.95, 0.6])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FractionallySizedBox(
                widthFactor: w,
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: skColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
        ],
      );
    }
    // 按屏幕宽度解码图片，避免整图分辨率解码导致掉帧与内存峰值
    final query = MediaQuery.of(context);
    final cacheWidth =
        (query.size.width * query.devicePixelRatio).round();
    final style = ref.watch(readingStyleProvider);
    final scheme = Theme.of(context).colorScheme;

    final processedMd = _applyHighlightInBody(widget.md, widget.searchKw, widget.currentHit);

    return Markdown(
      data: processedMd,
      inlineSyntaxes: [
        _HighlightSelSyntax(),
        _HighlightSyntax(),
      ],
      builders: {
        'highlight': _HighlightBuilder(),
        'highlight_sel': _HighlightSelBuilder(),
      },
      imageDirectory: widget.rootDir,
      imageBuilder: (uri, title, alt) {
        try {
          final path = uri.toString();
          Widget thumb;
          String? localPath;
          if (!path.startsWith('http')) {
            localPath = p.join(widget.rootDir, path);
            final file = File(localPath);
            if (!file.existsSync()) throw Exception('图片不存在: $localPath');
            thumb = Image.file(
              file,
              cacheWidth: cacheWidth,
              errorBuilder: (_, ___, ____) => Container(
                width: 48, height: 48, color: scheme.errorContainer,
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_outlined, size: 24, color: scheme.onErrorContainer),
              ),
            );
          } else {
            thumb = Image.network(
              path,
              cacheWidth: cacheWidth,
              errorBuilder: (_, ___, ____) => Container(
                width: 48, height: 48, color: scheme.errorContainer,
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_outlined, size: 24, color: scheme.onErrorContainer),
              ),
            );
          }
          if (localPath != null) {
            return GestureDetector(
              onTap: () => showDialog(
                context: context,
                useSafeArea: false,
                barrierColor: Colors.black87,
                builder: (ctx) => Dialog(
                  insetPadding: EdgeInsets.zero,
                  backgroundColor: Colors.transparent,
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: Container(
                      constraints: const BoxConstraints.expand(),
                      color: Colors.black,
                      child: Image.file(
                        File(localPath!),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white, size: 64),
                      ),
                    ),
                  ),
                ),
              ),
              child: thumb,
            );
          }
          return thumb;
        } catch (e, st) {
          debugPrint('[ReadPage] image load failed: $e\n$st');
          return Container(
            width: 64, height: 64, color: scheme.errorContainer,
            alignment: Alignment.center,
            child: Icon(Icons.broken_image_outlined, size: 32, color: scheme.onErrorContainer),
          );
        }
      },
      onTapLink: (text, href, title) async {
        if (href != null) {
          await launchUrl(Uri.parse(href));
        }
      },
      // 以主题默认样式为基底再覆盖：直接 MarkdownStyleSheet(...) 构造
      // 会把未传字段置 null，strong/链接等样式全部丢失（粗体失效的根因）
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: TextStyle(
          fontSize: style.fontSize,
          height: style.lineHeight,
        ),
        // 引用块是文章附加文字：弱化处理——无彩色底，
        // 仅浅色表面 + 细分隔线 + 更小字号，视觉上退居正文之后
        blockquote: TextStyle(
          fontSize: style.fontSize - 2,
          height: style.lineHeight,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        blockquoteDecoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 2,
            ),
          ),
        ),
      ),
      // 与页面共用滚动，避免正文内再滚动
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
    );
  }
}

/// 评论区：展示某篇文章的全部笔记（时间倒序）。
class _CommentSection extends ConsumerWidget {
  final String collectionId;
  final Future<void> Function(CollectionNote note) onDelete;

  const _CommentSection({
    required this.collectionId,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(collectionNotesProvider(collectionId));
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text('评论区', style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            Text(
              '${notesAsync.valueOrNull?.length ?? 0} 条',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...notesAsync.when(
          loading: () => const [
            Padding(
              padding: EdgeInsets.all(8),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ],
          error: (e, _) => [Text('加载笔记失败：$e')],
          data: (notes) {
            if (notes.isEmpty) {
              return [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '还没有笔记，来写第一条吧',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              ];
            }
            return [
              for (final n in notes) _NoteItem(note: n, onDelete: () => onDelete(n)),
            ];
          },
        ),
      ],
    );
  }
}

class _NoteItem extends StatelessWidget {
  final CollectionNote note;
  final VoidCallback onDelete;

  const _NoteItem({required this.note, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              Icons.person,
              size: 16,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '我',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('MM-dd HH:mm').format(note.createdAt),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    note.content,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: '删除',
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _HighlightSyntax extends md.InlineSyntax {
  _HighlightSyntax() : super(r'<<<HL>>>(.*?)<<</HL>>>');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final text = match.group(1)!;
    parser.addNode(md.Element.text('highlight', text));
    return true;
  }
}

class _HighlightSelSyntax extends md.InlineSyntax {
  _HighlightSelSyntax() : super(r'<<<HLS>>>(.*?)<<</HLS>>>');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final text = match.group(1)!;
    parser.addNode(md.Element.text('highlight_sel', text));
    return true;
  }
}

class _HighlightBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return Text.rich(
      TextSpan(
        text: element.textContent,
        style: preferredStyle?.copyWith(
          backgroundColor: const Color(0xFFFFD95E),
          color: const Color(0xFF4A3800),
        ),
      ),
    );
  }
}

class _HighlightSelBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return Text.rich(
      TextSpan(
        text: element.textContent,
        style: preferredStyle?.copyWith(
          backgroundColor: const Color(0xFFFF6B6B),
          color: const Color(0xFFFFFFFF),
          decoration: TextDecoration.underline,
          decorationColor: const Color(0xFFFFFFFF),
          decorationThickness: 2,
        ),
      ),
    );
  }
}
