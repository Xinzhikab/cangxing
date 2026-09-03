import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fav_app/features/treasure_spots/data/models/treasure_spot.dart';
import 'package:fav_app/features/treasure_spots/data/models/spot_folder.dart';
import 'package:fav_app/features/treasure_spots/data/providers/spot_repository_provider.dart';
import 'package:fav_app/features/treasure_spots/data/providers/spot_folder_repository_provider.dart';

class SpotEditPage extends ConsumerStatefulWidget {
  const SpotEditPage({
    super.key,
    // 不再依赖 widget.spotId；统一从 route settings.extra 读取
  });

  @override
  ConsumerState<SpotEditPage> createState() => _SpotEditPageState();
}

class _SpotEditPageState extends ConsumerState<SpotEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;
  late final TextEditingController _noteCtrl;
  late final TextEditingController _tagInputCtrl;

  late PlaceType _type;
  String? _folderId;
  late List<String> _tags;
  late List<String> _images;
  bool _saving = false;
  TreasureSpot? _editing;
  bool _dataLoaded = false; // 只在首次拿到数据时回填表单

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
    _latCtrl = TextEditingController();
    _lngCtrl = TextEditingController();
    _noteCtrl = TextEditingController();
    _tagInputCtrl = TextEditingController();
    _type = PlaceType.other;
    _tags = [];
    _images = [];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _noteCtrl.dispose();
    _tagInputCtrl.dispose();
    super.dispose();
  }

  /// 从当前 route 的 settings.extra 读取 spotId（go_router 通过 push extra 传入）
  String? get _spotIdFromRoute {
    final route = ModalRoute.of(context);
    final extra = route?.settings.arguments;
    if (extra is String) return extra;
    return null;
  }

  bool get _isEditing => _spotIdFromRoute != null;

  void _addTagFromInput() {
    final t = _tagInputCtrl.text.trim();
    if (t.isEmpty) return;
    if (!_tags.contains(t)) {
      setState(() => _tags.add(t));
    }
    _tagInputCtrl.clear();
  }

  Future<void> _pickImages() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;
      final paths = result.files
          .map((f) => f.path)
          .whereType<String>()
          .where((p) => p.isNotEmpty)
          .toList();
      if (paths.isNotEmpty) {
        setState(() => _images.addAll(paths));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败：$e')),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  Future<void> _showLocationSheet() async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '定位当前位置',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('获取当前位置...'),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('手动输入'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      double? lat;
      double? lng;
      if (_latCtrl.text.trim().isNotEmpty) {
        lat = double.tryParse(_latCtrl.text.trim());
      }
      if (_lngCtrl.text.trim().isNotEmpty) {
        lng = double.tryParse(_lngCtrl.text.trim());
      }

      final notifier = ref.read(spotListNotifierProvider.notifier);

      if (_isEditing && _editing != null) {
        final updated = _editing!.copyWith(
          name: _nameCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          lat: lat,
          lng: lng,
          placeType: PlaceTypeEnums.keyOf(_type),
          folderId: _folderId,
          clearFolderId: _folderId == null,
          tags: _tags,
          note: _noteCtrl.text.trim(),
          images: _images,
        );
        await notifier.updateSpot(updated);
      } else {
        final spot = TreasureSpot(
          id: '', // 空字符串 → Repository 内部会生成 UUID
          name: _nameCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          lat: lat,
          lng: lng,
          placeType: PlaceTypeEnums.keyOf(_type),
          folderId: _folderId,
          tags: _tags,
          note: _noteCtrl.text.trim(),
          images: _images,
        );
        await notifier.createSpot(spot);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    }
  }

  /// 一次性回填（仅当 spot 有数据且未回填过）
  void _applyIfNeeded(TreasureSpot? spot) {
    if (_dataLoaded || spot == null) return;
    _dataLoaded = true;
    _editing = spot;
    _nameCtrl.text = spot.name;
    _addressCtrl.text = spot.address;
    _latCtrl.text = spot.lat?.toString() ?? '';
    _lngCtrl.text = spot.lng?.toString() ?? '';
    _noteCtrl.text = spot.note;
    _type = spot.placeTypeEnum; // placeTypeEnum 是枚举形式
    _folderId = spot.folderId;
    _tags = List.from(spot.tags);
    _images = List.from(spot.images);
  }

  @override
  Widget build(BuildContext context) {
    final spotId = _spotIdFromRoute;
    // 如果是编辑模式，watch 详情；否则返回 null
    final spotAsync = spotId != null
        ? ref.watch(spotDetailProvider(spotId))
        : const AsyncValue<TreasureSpot?>.data(null);

    // 详情加载完成后一次性回填
    spotAsync.whenData((s) => _applyIfNeeded(s));

    final foldersAsync = ref.watch(spotFolderListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑地点' : '添加地点'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 加载中蒙层（只在编辑模式且首次加载中显示）
            if (spotAsync.isLoading && _isEditing)
              const LinearProgressIndicator(),
            const SizedBox(height: 12),
            // 名称
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '地点名称 *',
                hintText: '例如：巷口咖啡',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.place),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请输入地点名称' : null,
            ),
            const SizedBox(height: 16),
            // 地址
            TextFormField(
              controller: _addressCtrl,
              decoration: InputDecoration(
                labelText: '地址',
                hintText: '选填，例如：北京市朝阳区...',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.location_on_outlined),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.pin_drop),
                  tooltip: '定位当前位置',
                  onPressed: _showLocationSheet,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 经纬度
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _latCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: true),
                    decoration: const InputDecoration(
                      labelText: '纬度 Lat',
                      hintText: '例如：39.9042',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lngCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: true),
                    decoration: const InputDecoration(
                      labelText: '经度 Lng',
                      hintText: '例如：116.4074',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // 地点类型
            Text(
              '地点类型',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: PlaceTypeEnums.all.map((info) {
                final selected = _type == info.type;
                return ChoiceChip(
                  avatar: Icon(
                    info.icon,
                    size: 16,
                  ),
                  label: Text(info.label),
                  selected: selected,
                  onSelected: (v) {
                    if (v) setState(() => _type = info.type);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            // 所属文件夹
            Text(
              '所属文件夹',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            foldersAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('加载失败：$e'),
              data: (folders) => InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: _folderId,
                    hint: const Text('未归类'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('未归类'),
                      ),
                      for (final f in folders)
                        DropdownMenuItem<String>(
                          value: f.id,
                          child: Row(
                            children: [
                              Icon(f.iconData, size: 18, color: f.color),
                              const SizedBox(width: 8),
                              Text(f.name),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _folderId = v),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // 标签
            Text(
              '标签',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (int i = 0; i < _tags.length; i++)
                  InputChip(
                    label: Text('#${_tags[i]}'),
                    onDeleted: () => setState(() => _tags.removeAt(i)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagInputCtrl,
                    decoration: const InputDecoration(
                      hintText: '输入标签后回车或点右侧 + 添加',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addTagFromInput(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _addTagFromInput,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // 备注
            TextFormField(
              controller: _noteCtrl,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: '备注',
                hintText: '营业时间、推荐菜、避坑提示等',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            // 图片列表
            Text(
              '图片',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  if (i == _images.length) {
                    return GestureDetector(
                      onTap: _pickImages,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_photo_alternate_outlined),
                              SizedBox(height: 4),
                              Text('添加', style: TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  final path = _images[i];
                  return SizedBox(
                    width: 100,
                    height: 100,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image(
                            image: _imageProvider(path),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: const Icon(Icons.broken_image),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeImage(i),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(2),
                              child: const Icon(Icons.close,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),
            // 保存按钮
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text('保存中...'),
                        ],
                      )
                    : const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ImageProvider _imageProvider(String path) {
    if (path.startsWith('http')) {
      return NetworkImage(path);
    }
    if (path.startsWith('assets/')) {
      return AssetImage(path);
    }
    return FileImage(path);
  }
}
