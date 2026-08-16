import 'package:flutter/material.dart';

/// 转录完成后的标签确认对话框：AI 标签仅是建议，用户勾选/补选后才保存。
/// 文件夹由 AI 静默归一化自动应用，不在 UI 中显示。
///
/// 返回值：
/// - null：用户取消（整个保存中止）
/// - 非 null：确认后的标签列表（可为空）
Future<List<String>?> showTagConfirmDialog(
  BuildContext context, {
  required List<String> suggested,
  required List<String> existing,
}) {
  return showDialog<List<String>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _TagConfirmDialog(
      suggested: suggested,
      existing: existing,
    ),
  );
}

class _TagConfirmDialog extends StatefulWidget {
  final List<String> suggested;
  final List<String> existing;

  const _TagConfirmDialog({
    required this.suggested,
    required this.existing,
  });

  @override
  State<_TagConfirmDialog> createState() => _TagConfirmDialogState();
}

class _TagConfirmDialogState extends State<_TagConfirmDialog> {
  late final Set<String> _selected;
  late final TextEditingController _inputCtrl;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.suggested};
    _inputCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  void _addInput() {
    final t = _inputCtrl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _selected.add(t);
      _inputCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('确认标签'),
      // scrollable 让整段内容可滚动，避免小屏/弹键盘时底部溢出
      scrollable: true,
      content: ListenableBuilder(
        listenable: _inputCtrl,
        builder: (context, _) {
          // 已有标签中未被 AI 推荐的，供用户补选；手动输入时按包含关系过滤
          final query = _inputCtrl.text.trim().toLowerCase();
          final others = widget.existing
              .where((t) => !widget.suggested.contains(t))
              .where((t) => query.isEmpty || t.toLowerCase().contains(query))
              .toList(growable: false);
          return SizedBox(
            width: double.maxFinite,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AI 建议标签（已预选，点击可取消勾选）：',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (widget.suggested.isEmpty)
                  Text(
                    'AI 未建议标签',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontStyle: FontStyle.italic),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in widget.suggested)
                        FilterChip(
                          label: Text(t),
                          selected: _selected.contains(t),
                          onSelected: (v) => setState(
                              () => v ? _selected.add(t) : _selected.remove(t)),
                        ),
                    ],
                  ),
                if (others.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '已有标签（点击补选）：',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in others)
                            FilterChip(
                              label: Text(t),
                              selected: _selected.contains(t),
                              onSelected: (v) => setState(
                                  () => v ? _selected.add(t) : _selected.remove(t)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputCtrl,
                        decoration: const InputDecoration(
                          hintText: '手动添加标签',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _addInput(),
                      ),
                    ),
                    IconButton(
                      tooltip: '添加',
                      icon: const Icon(Icons.add),
                      onPressed: _addInput,
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('取消保存'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, _selected.toList()..sort()),
          child: const Text('确认保存'),
        ),
      ],
    );
  }
}
