import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/core/utils/app_logger.dart';
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

class _ExtractBundle {
  final String text;
  final List<String> images;
  final String author;
  final String publishedAt;
  final String title;
  final List<String>? log;
  const _ExtractBundle({
    required this.text,
    this.images = const [],
    this.author = '',
    this.publishedAt = '',
    this.title = '',
    this.log,
  });
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

    if (initialText.isEmpty) {
      SharedPreferences.getInstance().then((p) {
        final saved = p.getString('draft_raw_input');
        final ts = p.getInt('draft_ts');
        if (saved != null && ts != null) {
          final diff = DateTime.now().millisecondsSinceEpoch - ts;
          if (diff < const Duration(minutes: 30).inMilliseconds) {
            if (!mounted) return;
            showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('恢复草稿'),
                content: Text('检测到 30 分钟内的编辑草稿，共 ${saved.length} 字。是否恢复？'),
                actions: [
                  TextButton(onPressed: () {
                    Navigator.pop(ctx, false);
                    p.remove('draft_raw_input');
                    p.remove('draft_ts');
                  }, child: const Text('丢弃')),
                  FilledButton(onPressed: () {
                    Navigator.pop(ctx, true);
                  }, child: const Text('恢复')),
                ],
              ),
            ).then((ok) {
              if (!mounted) return;
              if (ok == true) {
                _rawInputCtrl.text = saved;
                setState(() {
                  _selectedType = TypeDetector.detectType(saved);
                });
              }
              p.remove('draft_raw_input');
              p.remove('draft_ts');
            });
          } else {
            p.remove('draft_raw_input');
            p.remove('draft_ts');
          }
        }
      });
    }

    // 每次进入保存页都重置转录状态：清掉上次会话的成功/失败条幅与日志
    Future.microtask(() {
      if (mounted) {
        ref.read(saveControllerProvider.notifier).reset();
      }
    });
  }

  @override
  void dispose() {
    if (_rawInputCtrl.text.trim().isNotEmpty) {
      SharedPreferences.getInstance().then((p) {
        p.setString('draft_raw_input', _rawInputCtrl.text);
        p.setInt('draft_ts', DateTime.now().millisecondsSinceEpoch);
      });
    }
    ref.read(saveControllerProvider.notifier).cancel();
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
      _selectedType = CollectionEnums.typeToSql(CollectionType.article)!;
      _saveOnlyRaw = false;
      _category = [AppConstants.defaultCategoryName];
    });
    ref.read(saveControllerProvider.notifier).toggleSaveOnlyRaw(false);
  }

  Future<String?> _tryDioFetch(String url) async {
    try {
      final fetched = await ref.read(webContentFetcherProvider).fetch(url);
      if (fetched.text.trim().isNotEmpty) {
        return fetched.text;
      }
    } catch (e, st) {
      ref.read(appLoggerProvider).warn('SavePage', '抓取（Dio 直连）失败：$e', st);
    }
    return null;
  }

  Future<_ExtractBundle?> _tryWebViewFallback(String url) async {
    if (!mounted) return null;
    final extractor = HeadlessWebExtractor(
      url: url,
      cookies: ref.read(cookieListProvider).valueOrNull ?? const [],
    );
    final rendered = await extractor.start(context);
    if (rendered != null && rendered.text.trim().isNotEmpty) {
      return _ExtractBundle(
        text: rendered.text,
        images: rendered.images,
        author: rendered.author,
        publishedAt: rendered.publishedAt,
        title: rendered.title,
        log: rendered.log,
      );
    }
    return null;
  }

  Future<void> _doSave() async {
    final input = _rawInputCtrl.text;
    String? preContent;
    var preImages = <String>[];
    var preAuthor = '';
    var prePublishedAt = '';
    var preTitle = '';
    List<String>? preExtractLog;
    final isUrl = WebContentFetcher.isLikelyUrl(input);
    final shouldTryWebview = isUrl && !_saveOnlyRaw;
    if (shouldTryWebview) {
      setState(() => _extracting = true);
      try {
        final dioText = await _tryDioFetch(input);
        if (dioText != null) {
          preContent = dioText;
          final svcFetched = await ref.read(webContentFetcherProvider).fetch(input);
          preImages = svcFetched.images;
          preAuthor = svcFetched.author;
          prePublishedAt = svcFetched.publishedAt;
        } else {
          final wv = await _tryWebViewFallback(input);
          if (wv != null) {
            preContent = wv.text;
            preImages = wv.images;
            preAuthor = wv.author;
            prePublishedAt = wv.publishedAt;
            preTitle = wv.title;
            preExtractLog = wv.log;
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
      builder: (context) => AlertDialog(
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
                  onTap: () {
                    setState(() {
                      _category = [AppConstants.defaultCategoryName];
                    });
                    context.pop();
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    ref.listen<AsyncValue<SaveState>>(saveControllerProvider, (prev, next) {
      final prevUi = prev?.valueOrNull?.uiState;
      final nextUi = next.valueOrNull?.uiState;
      if (prevUi != SaveUiState.success && nextUi == SaveUiState.success) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final newId = next.valueOrNull?.lastCollectionId;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('收藏成功 ✓'),
              behavior: SnackBarBehavior.floating,
              action: newId == null
                  ? null
                  : SnackBarAction(
                      label: '去查看',
                      onPressed: () {
                        context.go('/read/$newId');
                      },
                    ),
            ),
          );
          Navigator.of(context).pop();
        });
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('保存收藏'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListenableBuilder(
          listenable: _rawInputCtrl,
          builder: (context, _) {
            return Column(
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
                      label: Text(CollectionEnums.typeLabel(CollectionType.article)),
                      selected: _selectedType ==
                          CollectionEnums.typeToSql(CollectionType.article),
                      onSelected: (_) {
                        setState(() {
                          _selectedType =
                              CollectionEnums.typeToSql(CollectionType.article)!;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(CollectionEnums.typeLabel(CollectionType.comment)),
                      selected: _selectedType ==
                          CollectionEnums.typeToSql(CollectionType.comment),
                      onSelected: (_) {
                        setState(() {
                          _selectedType =
                              CollectionEnums.typeToSql(CollectionType.comment)!;
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
                Consumer(
                  builder: (_, ref, __) {
                    final st = ref.watch(saveControllerProvider).valueOrNull;
                    final ui = st?.uiState;
                    if (ui == SaveUiState.failed) {
                      return Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: FilledButton.icon(
                                onPressed: () {
                                  ref.read(saveControllerProvider.notifier).retryLast();
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('重试保存'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: scheme.error,
                                  foregroundColor: scheme.onError,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                onPressed: () {
                                  ref.read(saveControllerProvider.notifier).reset();
                                },
                                child: const Text('重新输入'),
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: _canSave ? _doSave : null,
                        child: const Text('保存'),
                      ),
                    );
                  },
                ),
              ],
            );
          },
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

Widget _logEntry(BuildContext context, String line) {
  final scheme = Theme.of(context).colorScheme;
  final isWarn = line.contains('⚠️');
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Text(
      line,
      style: TextStyle(
        fontSize: 12,
        fontFamily: 'monospace',
        color: isWarn ? scheme.error : null,
        fontWeight: isWarn ? FontWeight.w500 : null,
      ),
    ),
  );
}

/// 失败内联提示：单行紧凑提示替代原大卡片条幅。
/// 原文已由 controller 自动降级保存；详细日志通过复制带走。
class _FailureInline extends StatefulWidget {
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

  @override
  State<_FailureInline> createState() => _FailureInlineState();
}

class _FailureInlineState extends State<_FailureInline> {
  bool _expanded = false;

  String _buildCopyText() {
    final buf = StringBuffer();
    buf.writeln('收藏 App 转录失败报告');
    buf.writeln('时间：${DateTime.now().toIso8601String()}');
    buf.writeln('失败原因：${widget.reason?.name ?? 'unknown'}');
    buf.writeln('错误信息：${widget.message ?? '无'}');
    if (widget.log.isNotEmpty) {
      buf.writeln('--- 转录日志 ---');
      for (final l in widget.log) {
        buf.writeln(l);
      }
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message ?? widget.reason?.name ?? '未知错误';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
            if (widget.log.isNotEmpty)
              IconButton(
                tooltip: _expanded ? '收起日志' : '查看转录日志',
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() => _expanded = !_expanded);
                },
              ),
            TextButton(
              onPressed: widget.onRetry,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('重试'),
            ),
            if (widget.onEdit != null)
              IconButton(
                tooltip: '编辑收藏信息',
                icon: const Icon(Icons.edit, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: widget.onEdit,
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
        ),
        if (_expanded && widget.log.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in widget.log) _logEntry(context, line),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 成功内联提示：单行紧凑提示替代原大卡片条幅，与失败提示形式一致。
/// 日志详情通过复制带走；保存的收藏可点「编辑」补全元信息。
class _SuccessInline extends StatefulWidget {
  final List<String> log;
  final VoidCallback? onEdit;

  const _SuccessInline({required this.log, this.onEdit});

  @override
  State<_SuccessInline> createState() => _SuccessInlineState();
}

class _SuccessInlineState extends State<_SuccessInline> {
  bool _expanded = false;

  String _buildCopyText() {
    final buf = StringBuffer();
    buf.writeln('收藏 App 转录成功报告');
    buf.writeln('时间：${DateTime.now().toIso8601String()}');
    if (widget.log.isNotEmpty) {
      buf.writeln('--- 转录日志 ---');
      for (final l in widget.log) {
        buf.writeln(l);
      }
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
            if (widget.log.isNotEmpty)
              IconButton(
                tooltip: _expanded ? '收起日志' : '查看转录日志',
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() => _expanded = !_expanded);
                },
              ),
            if (widget.onEdit != null)
              TextButton(
                onPressed: widget.onEdit,
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
        ),
        if (_expanded && widget.log.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in widget.log) _logEntry(context, line),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
