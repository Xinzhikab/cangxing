import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/collections/data/providers/collection_repository_provider.dart';
import 'package:fav_app/features/collections/data/providers/collections_list_controller.dart';

/// 编辑弹窗的返回值。clearDate 区分「未设置日期」与「清空原日期」。
class MetaEditResult {
  final String title;
  final String author;
  final String platform;
  final DateTime? publishedAt;
  final bool clearDate;
  final List<String> tags;

  const MetaEditResult({
    required this.title,
    required this.author,
    required this.platform,
    required this.publishedAt,
    required this.clearDate,
    required this.tags,
  });
}

/// 收藏元信息编辑弹窗：标题 / 作者 / 平台 / 发布时间 / 标签。
/// 预填当前值，用户确认修改后由 [showMetaEditDialog] 回写数据库。
/// 标签支持手动输入新增 + 从已有标签（标签注册表/全部收藏）点选复用。
class MetaEditDialog extends ConsumerStatefulWidget {
  final String initialTitle;
  final String initialAuthor;
  final String initialPlatform;
  final DateTime? initialPublishedAt;
  final List<String> initialTags;

  const MetaEditDialog({
    super.key,
    required this.initialTitle,
    required this.initialAuthor,
    required this.initialPlatform,
    required this.initialPublishedAt,
    required this.initialTags,
  });

  @override
  ConsumerState<MetaEditDialog> createState() => _MetaEditDialogState();
}

class _MetaEditDialogState extends ConsumerState<MetaEditDialog> {
  static const Map<String, String> _platformOptions = {
    SourcePlatform.xiaoheihe: '小黑盒',
    SourcePlatform.douyin: '抖音',
    SourcePlatform.coolapk: '酷安',
    SourcePlatform.other: '其他',
  };

  late final TextEditingController _titleCtrl;
  late final TextEditingController _authorCtrl;
  late final TextEditingController _tagCtrl;
  late String _platform;
  DateTime? _publishedAt;
  late final List<String> _tags;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _authorCtrl = TextEditingController(text: widget.initialAuthor);
    _tagCtrl = TextEditingController();
    _platform = _platformOptions.containsKey(widget.initialPlatform)
        ? widget.initialPlatform
        : SourcePlatform.other;
    _publishedAt = widget.initialPublishedAt;
    _tags = List.of(widget.initialTags);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  void _addTag() {
    final t = _tagCtrl.text.trim();
    if (t.isEmpty || _tags.contains(t)) {
      _tagCtrl.clear();
      return;
    }
    setState(() {
      _tags.add(t);
      _tagCtrl.clear();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _publishedAt ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _publishedAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    final dateText = _publishedAt == null
        ? '未设置'
        : '${_publishedAt!.year}-${_publishedAt!.month.toString().padLeft(2, '0')}-${_publishedAt!.day.toString().padLeft(2, '0')}';
    return AlertDialog(
      title: const Text('编辑收藏信息'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: '标题',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _authorCtrl,
              decoration: const InputDecoration(
                labelText: '作者',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _platform,
              decoration: const InputDecoration(
                labelText: '平台',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final e in _platformOptions.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) =>
                  setState(() => _platform = v ?? SourcePlatform.other),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '发布时间',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(dateText),
                  ),
                ),
                IconButton(
                  tooltip: '选择日期',
                  icon: const Icon(Icons.calendar_month),
                  onPressed: _pickDate,
                ),
                if (_publishedAt != null)
                  IconButton(
                    tooltip: '清空日期',
                    icon: const Icon(Icons.event_busy),
                    onPressed: () => setState(() => _publishedAt = null),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_tags.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in _tags)
                    InputChip(
                      label: Text(t),
                      onDeleted: () => setState(() => _tags.remove(t)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagCtrl,
                    decoration: const InputDecoration(
                      hintText: '添加标签（可从下方已有标签点选）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addTag(),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                IconButton(
                  tooltip: '添加标签',
                  icon: const Icon(Icons.add),
                  onPressed: _addTag,
                ),
              ],
            ),
            // 已有标签点选：标签注册表 + 全部收藏标签聚合；
            // 输入框有内容时按前缀/包含过滤，已添加的不再展示
            ref.watch(allTagsProvider).maybeWhen(
                  data: (counts) {
                    final query = _tagCtrl.text.trim().toLowerCase();
                    final candidates = counts.keys
                        .where((t) => !_tags.contains(t))
                        .where((t) =>
                            query.isEmpty || t.toLowerCase().contains(query))
                        .toList()
                      ..sort((a, b) {
                        // 输入过滤时前缀命中优先，其次按使用次数降序
                        final ap = a.toLowerCase().startsWith(query) ? 0 : 1;
                        final bp = b.toLowerCase().startsWith(query) ? 0 : 1;
                        if (ap != bp) return ap - bp;
                        return (counts[b] ?? 0).compareTo(counts[a] ?? 0);
                      });
                    if (candidates.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '已有标签（点击添加）',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 120),
                            child: SingleChildScrollView(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final t in candidates)
                                    ActionChip(
                                      label: Text(
                                        counts[t]! > 0 ? '$t (${counts[t]})' : t,
                                      ),
                                      onPressed: () =>
                                          setState(() => _tags.add(t)),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              MetaEditResult(
                title: _titleCtrl.text,
                author: _authorCtrl.text,
                platform: _platform,
                publishedAt: _publishedAt,
                clearDate:
                    widget.initialPublishedAt != null && _publishedAt == null,
                tags: List.of(_tags),
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 打开元信息编辑弹窗并保存修改。
///
/// 读取收藏当前值 → 弹窗编辑 → 回写数据库 → 失效列表/统计/标签缓存。
/// 返回是否实际更新（false = 取消或收藏不存在）。
/// 注意：详情页缓存（collectionDetailProvider）由调用方自行失效。
Future<bool> showMetaEditDialog(
  BuildContext context,
  WidgetRef ref,
  String collectionId,
) async {
  final repo = ref.read(collectionRepositoryProvider);
  final col = await repo.get(collectionId);
  if (col == null) return false;
  if (!context.mounted) return false;
  final result = await showDialog<MetaEditResult>(
    context: context,
    builder: (_) => MetaEditDialog(
      initialTitle: col.title,
      initialAuthor: col.author,
      initialPlatform: col.sourcePlatform,
      initialPublishedAt: col.publishedAt,
      initialTags: col.tags,
    ),
  );
  if (result == null) return false;
  // copyWith 无法把日期置空，用构造函数重建；contentMd 留空，
  // repo.update 对空正文会保留原文件不覆盖
  final updated = Collection(
    id: col.id,
    title: result.title.trim(),
    type: col.type,
    sourcePlatform: result.platform,
    sourceUrl: col.sourceUrl,
    author: result.author.trim(),
    publishedAt:
        result.clearDate ? null : (result.publishedAt ?? col.publishedAt),
    collectedAt: col.collectedAt,
    category: col.category,
    images: col.images,
    tags: result.tags,
    note: col.note,
    status: col.status,
    reviewDueAt: col.reviewDueAt,
    rawInput: col.rawInput,
  );
  await repo.update(updated);
  ref.invalidate(collectionsListProvider);
  ref.invalidate(groupStatsProvider);
  ref.invalidate(allTagsProvider);
  return true;
}
