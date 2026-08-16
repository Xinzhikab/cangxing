import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/features/collections/data/models/category.dart';
import 'package:fav_app/features/collections/data/providers/category_tree_provider.dart';
import 'package:fav_app/features/collections/presentation/widgets/meta_edit_dialog.dart';
import 'package:fav_app/features/settings/data/providers/cookie_provider.dart';
import 'package:fav_app/features/save/data/models/transcription_models.dart';
import 'package:fav_app/features/save/data/providers/save_controller.dart';
import 'package:fav_app/features/save/data/providers/transcription_providers.dart';
import 'package:fav_app/features/save/data/services/web_content_fetcher.dart';
import 'package:fav_app/features/save/data/utils/type_detector.dart';
import 'package:fav_app/features/save/presentation/pages/web_extract_page.dart';
import 'package:fav_app/features/save/presentation/widgets/tag_confirm_dialog.dart';

class SavePage extends ConsumerStatefulWidget {
  final Object? extra;

  const SavePage({
    super.key,
    this.extra,
  });

  @override
  ConsumerState<SavePage> createState() => _SavePageState();
}

class _SavePageState extends ConsumerState<SavePage> {
  late final TextEditingController _rawInputCtrl;
  late String _selectedType;
  late List<String> _category;
  late bool _saveOnlyRaw;
  /// 正在后台提取网页内容（无头 WebView，全程不显示提取页面）
  bool _extracting = false;

  @override
  void initState() {
    super.initState();
    String initialText = '';
    String? suggestType;

    if (widget.extra is String) {
      initialText = widget.extra as String;
    } else if (widget.extra is Map<String, dynamic>) {
      final map = widget.extra as Map<String, dynamic>;
      initialText = map['text'] as String? ?? '';
      suggestType = map['suggestType'] as String?;
    }

    _rawInputCtrl = TextEditingController(text: initialText);
    _selectedType = TypeDetector.detectType(initialText, suggested: suggestType);
    _category = [AppConstants.defaultCategoryName];
    _saveOnlyRaw = false;
    // 每次进入保存页都重置转录状态：清掉上次会话的成功/失败条幅与日志
    Future.microtask(() {
      if (mounted) {
        ref.read(saveControllerProvider.notifier).reset();
      }
    });
  }

  @override
  void dispose() {
    _rawInputCtrl.dispose();
    super.dispose();
  }

  bool get _canSave => _rawInputCtrl.text.trim().isNotEmpty && !_extracting;

  String get _categoryLabel => _category.isEmpty
      ? AppConstants.defaultCategoryName
      : _category.join('/');

  /// 导入剪贴板内容到输入框（清空后粘贴，避免拼接残留）
  Future<void> _importClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剪贴板为空')),
      );
      return;
    }
    _rawInputCtrl.text = text;
    // 手动同步：直接赋值不触发 onChanged，类型识别与状态重置在这里做
    setState(() {
      _selectedType = TypeDetector.detectType(text);
    });
    final st = ref.read(saveControllerProvider).valueOrNull;
    if (st != null &&
        st.uiState != SaveUiState.idle &&
        st.uiState != SaveUiState.processing) {
      ref.read(saveControllerProvider.notifier).reset();
    }
  }

  /// 全部清除：清空输入框并重置为初始状态（类型/仅存原文/转录结果）
  void _clearAll() {
    _rawInputCtrl.clear();
    ref.read(saveControllerProvider.notifier).reset();
    setState(() {
      _selectedType = 'article';
      _saveOnlyRaw = false;
      _category = [AppConstants.defaultCategoryName];
    });
    ref.read(saveControllerProvider.notifier).toggleSaveOnlyRaw(false);
  }

  Future<void> _doSave() async {
    final input = _rawInputCtrl.text;
    // 若是链接且非仅存原文，先尝试抓取正文；抓不到（JS 渲染站点）则用
    // 无头 WebView 后台渲染提取——全程不打开任何提取页面，用户无感
    String? preContent;
    var preImages = <String>[];
    var preAuthor = '';
    var prePublishedAt = '';
    var preTitle = '';
    List<String>? preExtractLog;
    final isUrl = WebContentFetcher.isLikelyUrl(input);
    if (isUrl && !_saveOnlyRaw) {
      setState(() => _extracting = true);
      try {
        try {
          final fetched = await ref.read(webContentFetcherProvider).fetch(input);
          preContent = fetched.text;
          preImages = fetched.images;
          preAuthor = fetched.author;
          prePublishedAt = fetched.publishedAt;
        } catch (_) {
          if (!mounted) return;
          final extractor = HeadlessWebExtractor(
            url: input,
            cookies: ref.read(cookieListProvider),
          );
          final rendered = await extractor.start(context);
          if (rendered != null && rendered.text.trim().isNotEmpty) {
            preContent = rendered.text;
            preImages = rendered.images;
            preAuthor = rendered.author;
            prePublishedAt = rendered.publishedAt;
            preTitle = rendered.title;
            preExtractLog = rendered.log;
          }
        }
      } finally {
        if (mounted) setState(() => _extracting = false);
      }
    }

    await ref.read(saveControllerProvider.notifier).save(
          rawInput: input,
          type: _selectedType,
          categoryPath: _category,
          saveOnlyRaw: _saveOnlyRaw,
          preFetchedContent: preContent,
          preFetchedImages: preImages,
          preFetchedAuthor: preAuthor,
          preFetchedPublishedAt: prePublishedAt,
          preFetchedTitle: preTitle,
          preExtractLog: preExtractLog,
          // AI 标签仅是建议：转录完成后弹确认框让用户勾选；
          // 文件夹由 AI 静默归一化自动应用，不在此显示
          onConfirmTags: (suggested, existing) async {
            if (!mounted) return suggested;
            return showTagConfirmDialog(
              context,
              suggested: suggested,
              existing: existing,
            );
          },
        );
  }

  /// 转录后编辑收藏元信息（标题/作者/平台/时间/标签），保存后回写数据库。
  Future<void> _openMetaEditor(String collectionId) async {
    final ok = await showMetaEditDialog(context, ref, collectionId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '收藏信息已更新' : '未修改')),
    );
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
        onTap: () {
          setState(() {
            _category = path;
          });
          context.pop();
        },
      ),
    );
    for (final child in node.children) {
      _buildPathTiles(child, byId, tiles, depth: depth + 1);
    }
  }

  Future<void> _openCategoryPicker() async {
    // 等分类列表加载完成再弹窗：valueOrNull 在未加载时为 null，
    // 会导致弹窗只显示硬编码的「未分类」
    List<Category> allCategories;
    try {
      allCategories = await ref.read(categoriesListProvider.future);
    } catch (_) {
      allCategories = const [];
    }
    if (!mounted) return;
    final byId = {for (final c in allCategories) c.id: c};
    final tree = ref.read(categoryTreeProvider);

    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择分类'),
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
            onTap: () {
              setState(() {
                _category = [AppConstants.defaultCategoryName];
              });
              context.pop();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('保存收藏'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 输入框工具行：导入剪贴板 / 全部清除
            Row(
              children: [
                TextButton.icon(
                  onPressed: _importClipboard,
                  icon: const Icon(Icons.content_paste, size: 18),
                  label: const Text('导入剪贴板'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _canSave || _saveOnlyRaw ? _clearAll : null,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('全部清除'),
                  style: TextButton.styleFrom(
                    foregroundColor:
                        Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
            Expanded(
              child: TextField(
                controller: _rawInputCtrl,
                maxLines: null,
                expands: true,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: '粘贴链接或文本...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                onChanged: (_) {
                  setState(() {});
                  // 用户开始输入新内容时，自动收起上次结果（成功/失败）条幅，
                  // 避免条幅常驻挡住输入区；需要复制日志/编辑信息请在此之前操作
                  final st = ref.read(saveControllerProvider).valueOrNull;
                  if (st != null &&
                      st.uiState != SaveUiState.idle &&
                      st.uiState != SaveUiState.processing) {
                    ref.read(saveControllerProvider.notifier).reset();
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('类型：'),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('文章'),
                  selected: _selectedType == 'article',
                  onSelected: (_) {
                    setState(() {
                      _selectedType = 'article';
                    });
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('评论'),
                  selected: _selectedType == 'comment',
                  onSelected: (_) {
                    setState(() {
                      _selectedType = 'comment';
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('分类：'),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(_categoryLabel),
                  selected: true,
                  onSelected: (_) => _openCategoryPicker(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: _saveOnlyRaw,
                  onChanged: (v) {
                    setState(() {
                      _saveOnlyRaw = v ?? false;
                    });
                    ref
                        .read(saveControllerProvider.notifier)
                        .toggleSaveOnlyRaw(_saveOnlyRaw);
                  },
                ),
                const Text('仅存原文稍后转录'),
              ],
            ),
            const SizedBox(height: 12),
            if (_extracting)
              Row(
                children: const [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('正在后台提取网页内容...'),
                  ),
                ],
              ),
            Consumer(
              builder: (_, ref, __) {
                final st = ref.watch(saveControllerProvider).valueOrNull;
                if (st == null) return const SizedBox.shrink();
                final ui = st.uiState;
                return Column(
                  children: [
                    if (ui == SaveUiState.processing && st.progress != null)
                      _ProgressBar(st.progress!),
                    if (ui == SaveUiState.failed)
                      _FailureInline(
                        reason: st.failureReason,
                        message: st.errorMessage,
                        log: st.log,
                        onRetry: _doSave,
                        onEdit: st.lastCollectionId == null
                            ? null
                            : () => _openMetaEditor(st.lastCollectionId!),
                      ),
                    if (ui == SaveUiState.success)
                      _SuccessInline(
                        log: st.log,
                        onEdit: st.lastCollectionId == null
                            ? null
                            : () => _openMetaEditor(st.lastCollectionId!),
                      ),
                  ],
                );
              },
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _canSave ? _doSave : null,
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final TranscriptionProgress progress;

  const _ProgressBar(this.progress);

  String _stepText(TranscriptionStep step) {
    switch (step) {
      case TranscriptionStep.fetching:
        return '正在抓取网页内容...';
      case TranscriptionStep.transcribing:
        return '正在 AI 转录...';
      case TranscriptionStep.downloadingImages:
        return '正在下载图片...';
      case TranscriptionStep.done:
        return '完成';
      case TranscriptionStep.failed:
        return '失败';
    }
  }

  @override
  Widget build(BuildContext context) {
    final showValue = progress.step == TranscriptionStep.downloadingImages &&
        (progress.total ?? 0) > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_stepText(progress.step)),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: showValue
              ? (progress.current ?? 0) / (progress.total!)
              : null,
        ),
      ],
    );
  }
}

/// 失败内联提示：单行紧凑提示替代原大卡片条幅。
/// 原文已由 controller 自动降级保存；详细日志通过复制带走。
class _FailureInline extends StatelessWidget {
  final TranscriptionFailureReason? reason;
  final String? message;
  final List<String> log;
  final VoidCallback onRetry;
  final VoidCallback? onEdit;

  const _FailureInline({
    required this.reason,
    required this.message,
    required this.log,
    required this.onRetry,
    this.onEdit,
  });

  String _buildCopyText() {
    final buf = StringBuffer();
    buf.writeln('收藏 App 转录失败报告');
    buf.writeln('时间：${DateTime.now().toIso8601String()}');
    buf.writeln('失败原因：${reason?.name ?? 'unknown'}');
    buf.writeln('错误信息：${message ?? '无'}');
    if (log.isNotEmpty) {
      buf.writeln('--- 转录日志 ---');
      for (final l in log) {
        buf.writeln(l);
      }
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final msg = message ?? reason?.name ?? '未知错误';
    return Row(
      children: [
        Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '转录失败：$msg（原文已保存）',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: Colors.red.shade700),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('重试'),
        ),
        if (onEdit != null)
          IconButton(
            tooltip: '编辑收藏信息',
            icon: const Icon(Icons.edit, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
          ),
        IconButton(
          tooltip: '复制转录日志',
          icon: const Icon(Icons.copy, size: 18),
          visualDensity: VisualDensity.compact,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _buildCopyText()));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('转录日志已复制')),
            );
          },
        ),
      ],
    );
  }
}

/// 成功内联提示：单行紧凑提示替代原大卡片条幅，与失败提示形式一致。
/// 日志详情通过复制带走；保存的收藏可点「编辑」补全元信息。
class _SuccessInline extends StatelessWidget {
  final List<String> log;
  final VoidCallback? onEdit;

  const _SuccessInline({required this.log, this.onEdit});

  String _buildCopyText() {
    final buf = StringBuffer();
    buf.writeln('收藏 App 转录成功报告');
    buf.writeln('时间：${DateTime.now().toIso8601String()}');
    if (log.isNotEmpty) {
      buf.writeln('--- 转录日志 ---');
      for (final l in log) {
        buf.writeln(l);
      }
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '转录成功，已入库',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: Colors.green.shade700,
            ),
          ),
        ),
        if (onEdit != null)
          TextButton(
            onPressed: onEdit,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('编辑'),
          ),
        IconButton(
          tooltip: '复制转录日志',
          icon: const Icon(Icons.copy, size: 18),
          visualDensity: VisualDensity.compact,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _buildCopyText()));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('转录日志已复制')),
            );
          },
        ),
      ],
    );
  }
}
