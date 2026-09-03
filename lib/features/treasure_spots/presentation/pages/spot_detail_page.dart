import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fav_app/features/treasure_spots/data/models/treasure_spot.dart';
import 'package:fav_app/features/treasure_spots/data/providers/spot_repository_provider.dart';
import 'package:fav_app/features/treasure_spots/data/providers/spot_folder_repository_provider.dart';

/// 调起导航：高德 → 百度 → geo → comgooglemaps → 网页兜底
Future<void> launchNavigationDetail(BuildContext context, TreasureSpot spot) async {
  final name = Uri.encodeComponent(spot.name);
  final addr = Uri.encodeComponent(spot.address);
  final lat = spot.lat;
  final lng = spot.lng;

  final candidates = <String>[];
  if (lat != null && lng != null) {
    candidates.add('androidamap://navi?sourceApplication=fav_app&lat=$lat&lon=$lng&dev=0&style=2');
    candidates.add('iosamap://navi?sourceApplication=fav_app&lat=$lat&lon=$lng&dev=0&style=2');
    candidates.add('baidumap://map/direction?destination=latlng:$lat,$lng|name:$name&mode=driving&src=fav_app');
    candidates.add('geo:$lat,$lng?q=$name');
    candidates.add('comgooglemaps://?saddr=&daddr=$lat,$lng&directionsmode=driving');
  } else {
    candidates.add('geo:0,0?q=$addr');
  }
  final fallback = lat != null && lng != null
      ? 'https://uri.amap.com/marker?position=$lng,$lat&name=$name'
      : 'https://uri.amap.com/search?keyword=$addr';

  bool launched = false;
  for (final uri in candidates) {
    try {
      final u = Uri.parse(uri);
      if (await canLaunchUrl(u)) {
        await launchUrl(u, mode: LaunchMode.externalApplication);
        launched = true;
        break;
      }
    } catch (_) {}
  }
  if (!launched) {
    try {
      final u = Uri.parse(fallback);
      if (await canLaunchUrl(u)) {
        await launchUrl(u, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法打开地图应用，请手动导航')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开地图失败：$e')),
        );
      }
    }
  }
}

class SpotDetailPage extends ConsumerStatefulWidget {
  const SpotDetailPage({
    super.key,
    // 不再依赖 widget.spotId；从 route settings.extra 读取
  });

  @override
  ConsumerState<SpotDetailPage> createState() => _SpotDetailPageState();
}

class _SpotDetailPageState extends ConsumerState<SpotDetailPage> {
  final PageController _pageCtrl = PageController();
  int _pageIdx = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  /// 从当前 route 的 settings.extra 读取 spotId
  String get _spotIdFromRoute {
    final route = ModalRoute.of(context);
    final extra = route?.settings.arguments;
    if (extra is String) return extra;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final spotId = _spotIdFromRoute;
    final spotAsync = spotId.isNotEmpty
        ? ref.watch(spotDetailProvider(spotId))
        : const AsyncValue<TreasureSpot?>.data(null);
    return spotAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('加载中...')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('详情')),
        body: Center(child: Text('加载失败：$e')),
      ),
      data: (spot) {
        if (spot == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('详情')),
            body: const Center(child: Text('地点不存在或已删除')),
          );
        }
        return _buildBody(spot);
      },
    );
  }

  Widget _buildBody(TreasureSpot spot) {
    // spot.type 是 String(sql 值)
    final typeInfo = PlaceTypeEnums.infoOfKey(spot.type);
    final scheme = Theme.of(context).colorScheme;

    // 文件夹名称/图标/颜色：从 spotFolderDetailProvider 按 id 查
    String folderName = '未分类';
    IconData? folderIcon;
    Color? folderColor;
    if (spot.folderId != null && spot.folderId!.isNotEmpty) {
      final fAsync = ref.watch(spotFolderDetailProvider(spot.folderId!));
      final folder = fAsync.valueOrNull;
      if (folder != null) {
        folderName = folder.name;
        folderIcon = folder.icon; // 新增的 icon getter
        folderColor = folder.color;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          spot.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        children: [
          // 图片轮播
          if (spot.images.isNotEmpty)
            SizedBox(
              height: 260,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pageCtrl,
                    itemCount: spot.images.length,
                    onPageChanged: (i) => setState(() => _pageIdx = i),
                    itemBuilder: (_, i) => Image(
                      image: _imageProvider(spot.images[i]),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(typeInfo.icon, size: 80, color: scheme.primary),
                      ),
                    ),
                  ),
                  if (spot.images.length > 1)
                    Positioned(
                      bottom: 10,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          spot.images.length,
                          (i) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _pageIdx ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              color: i == _pageIdx
                                  ? scheme.primary
                                  : Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            Container(
              height: 200,
              color: scheme.surfaceContainerHighest,
              child: Icon(typeInfo.icon, size: 80, color: scheme.primary),
            ),
          const SizedBox(height: 16),
          // 名称 + 类型
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        spot.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(typeInfo.icon,
                              size: 14, color: scheme.onPrimaryContainer),
                          const SizedBox(width: 4),
                          Text(
                            typeInfo.label,
                            style: TextStyle(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (spot.address.isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.location_on_outlined,
                          color: scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          spot.address,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                if ((spot.lat != null && spot.lng != null))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.pin_drop_outlined,
                            size: 18, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(
                          // 使用 latLngText getter（任务要求的）
                          spot.latLngText,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // 一键导航大按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => launchNavigationDetail(context, spot),
                icon: const Icon(Icons.directions_walk, size: 22),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '一键导航',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 1),
          ),
          const SizedBox(height: 16),
          // 所属文件夹
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(
                  icon: folderIcon ?? Icons.folder,
                  iconColor: folderColor ?? scheme.primary,
                  label: '所属文件夹',
                  value: folderName,
                ),
                const SizedBox(height: 14),
                if (spot.tags.isNotEmpty) ...[
                  Text(
                    '标签',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in spot.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '#$t',
                            style: TextStyle(
                                color: scheme.onSecondaryContainer),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                if (spot.note.isNotEmpty) ...[
                  Text(
                    '备注',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      spot.note,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 40),
          // 编辑 / 删除按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await context.push<bool>(
                        '/treasure-spots/edit',
                        extra: spot.id,
                      );
                      if (ok == true && mounted) {
                        // 通过 refresh token 自动刷新；详情页返回 true 让上一层决定
                        Navigator.pop(context, true);
                      }
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('编辑'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                      side: BorderSide(color: scheme.error),
                    ),
                    onPressed: () => _confirmDelete(spot),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(TreasureSpot spot) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除地点'),
        content: Text('确定删除「${spot.name}」？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      // 使用 AsyncNotifier 删除；内部 bump refresh token
      await ref.read(spotListNotifierProvider.notifier).deleteSpot(spot.id);
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除')),
        );
      }
    }
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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 8),
        Text(
          '$label：',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}
