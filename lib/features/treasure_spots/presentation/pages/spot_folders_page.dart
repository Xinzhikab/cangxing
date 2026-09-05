import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fav_app/features/treasure_spots/data/models/spot_folder.dart';
import 'package:fav_app/features/treasure_spots/data/providers/spot_folder_repository_provider.dart';
import 'package:fav_app/features/treasure_spots/data/providers/spot_repository_provider.dart';

class SpotFoldersPage extends ConsumerWidget {
  const SpotFoldersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(spotFolderListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('文件夹管理')),
      body: foldersAsync.when(loading: () => const Center(child: CircularProgressIndicator()), error: (e, _) => Center(child: Text('加载失败：$e')), data: (folders) {
        if (folders.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.folder_outlined, size: 72, color: Theme.of(context).colorScheme.outline), const SizedBox(height: 16), const Text('暂无文件夹'), const SizedBox(height: 8), Text('点击右下角 + 创建文件夹', style: Theme.of(context).textTheme.bodySmall)]));
        return ListView.separated(padding: const EdgeInsets.all(8), itemCount: folders.length, separatorBuilder: (_, __) => const Divider(height: 1), itemBuilder: (_, i) {
          final f = folders[i];
          final cnt = ref.watch(folderSpotCountProvider(f.id)).valueOrNull ?? 0;
          return _FolderTile(folder: f, count: cnt);
        });
      }),
      floatingActionButton: FloatingActionButton(heroTag: 'add_spot_folder', onPressed: () => _showFolderDialog(context, ref), tooltip: '新建文件夹', child: const Icon(Icons.create_new_folder)),
    );
  }
}

class _FolderTile extends ConsumerWidget {
  final SpotFolder folder; final int count;
  const _FolderTile({required this.folder, required this.count});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    leading: CircleAvatar(backgroundColor: folder.color.withValues(alpha: 0.15), child: Icon(folder.icon, color: folder.color)),
    title: Text(folder.name),
    subtitle: Text('$count 个地点'),
    trailing: PopupMenuButton<_FolderAction>(onSelected: (action) async { switch (action) { case _FolderAction.edit: _showFolderDialog(context, ref, folder: folder); break; case _FolderAction.delete: _confirmDelete(context, ref); break; } }, itemBuilder: (_) => const [PopupMenuItem(value: _FolderAction.edit, child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.edit_outlined), title: Text('编辑'))), PopupMenuItem(value: _FolderAction.delete, child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('删除', style: TextStyle(color: Colors.red))))]),
  );

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    if (count > 0) {
      final choice = await showDialog<int>(context: context, builder: (ctx) => AlertDialog(title: const Text('删除文件夹'), content: Text('「${folder.name}」下还有 $count 个地点。\n\n• 仅删除文件夹：地点变为「未归类」\n• 删除文件夹及地点：永久删除所有地点'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, 0), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(ctx, 1), child: const Text('仅删文件夹')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error), onPressed: () => Navigator.pop(ctx, 2), child: const Text('全部删除'))]));
      if (choice == null || choice == 0) return;
      final spotNotifier = ref.read(spotListNotifierProvider.notifier);
      final folderNotifier = ref.read(spotFolderListNotifierProvider.notifier);
      if (choice == 2) { final repo = ref.read(spotRepositoryProvider); final spots = await repo.listByFolder(folder.id); for (final s in spots) await spotNotifier.deleteSpot(s.id); }
      await folderNotifier.deleteFolder(folder.id);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(choice == 2 ? '已删除「${folder.name}」及其下 $count 个地点' : '已删除文件夹，地点已移至未归类')));
    } else {
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('删除文件夹'), content: Text('确定删除空文件夹「${folder.name}」？'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error), onPressed: () => Navigator.pop(ctx, true), child: const Text('删除'))]));
      if (ok == true) { await ref.read(spotFolderListNotifierProvider.notifier).deleteFolder(folder.id); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除'))); }
    }
  }
}

enum _FolderAction { edit, delete }

Future<void> _showFolderDialog(BuildContext context, WidgetRef ref, {SpotFolder? folder}) {
  final isEdit = folder != null;
  final nameCtrl = TextEditingController(text: folder?.name ?? '');
  var icon = folder?.icon ?? FolderIconPresets.icons.first;
  var color = folder?.color ?? FolderColorPresets.colors.first;
  return showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setState) => AlertDialog(title: Text(isEdit ? '编辑文件夹' : '新建文件夹'), scrollable: true, content: SizedBox(width: 320, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    TextField(controller: nameCtrl, autofocus: true, decoration: const InputDecoration(labelText: '名称', border: OutlineInputBorder())),
    const SizedBox(height: 18),
    const Text('选择图标'),
    const SizedBox(height: 8),
    SizedBox(height: 180, child: GridView.count(crossAxisCount: 5, mainAxisSpacing: 6, crossAxisSpacing: 6, childAspectRatio: 1, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), children: FolderIconPresets.icons.map((i) { final selected = i.codePoint == icon.codePoint; return InkResponse(onTap: () => setState(() => icon = i), child: Container(decoration: BoxDecoration(color: selected ? color.withValues(alpha: 0.2) : Colors.transparent, border: Border.all(color: selected ? color : Colors.transparent), borderRadius: BorderRadius.circular(8)), child: Icon(i, color: selected ? color : null))); }).toList())),
    const SizedBox(height: 18),
    const Text('选择颜色'),
    const SizedBox(height: 8),
    Wrap(spacing: 8, runSpacing: 8, children: FolderColorPresets.colors.map((c) { final selected = c.value == color.value; return GestureDetector(onTap: () => setState(() => color = c), child: Container(width: 36, height: 36, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: selected ? (Theme.of(ctx).brightness == Brightness.dark ? Colors.white : Colors.black) : Colors.transparent, width: 2)), child: selected ? const Icon(Icons.check, color: Colors.white, size: 20) : null)); }).toList()),
  ])), actions: [
    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
    FilledButton(onPressed: () async { final name = nameCtrl.text.trim(); if (name.isEmpty) return; final notifier = ref.read(spotFolderListNotifierProvider.notifier); if (isEdit) { await notifier.updateFolder(folder!.copyWith(name: name, iconCodePoint: icon.codePoint, colorValue: color.value)); } else { await notifier.createFolder(name: name, icon: icon, color: color); } if (ctx.mounted) Navigator.pop(ctx); }, child: Text(isEdit ? '保存' : '创建')),
  ]))));
}
