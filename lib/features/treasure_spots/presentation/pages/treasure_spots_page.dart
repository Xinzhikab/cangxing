import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fav_app/features/treasure_spots/data/models/treasure_spot.dart';
import 'package:fav_app/features/treasure_spots/data/providers/spot_repository_provider.dart';
import 'package:fav_app/features/treasure_spots/data/providers/spot_folder_repository_provider.dart';

/// 调起导航：高德 → 百度 → geo → comgooglemaps → 网页兜底
Future<void> launchNavigation(BuildContext context, TreasureSpot spot) async {
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
  // 网页兜底
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

class TreasureSpotsPage extends ConsumerStatefulWidget {
  const TreasureSpotsPage({super.key});

  @override
  ConsumerState<TreasureSpotsPage> createState() => _TreasureSpotsPageState();
}

class _TreasureSpotsPageState extends ConsumerState<TreasureSpotsPage> {
  late final TextEditingController _searchCtrl;
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
    final scheme = Theme.of(context).colorScheme;
    final filter = ref.watch(treasureSpotsFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: _searchOpen
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '按名称搜索...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onChanged: (v) {
                  ref.read(treasureSpotsFilterProvider.notifier).state =
                      filter.copyWith(keyword: v);
                },
              )
            : const Text('宝藏地点'),
        actions: [
          if (_searchOpen)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '关闭搜索',
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                _searchCtrl.clear();
                ref.read(treasureSpotsFilterProvider.notifier).state =
                    filter.copyWith(keyword: '');
                setState(() => _searchOpen = false);
              },
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: '搜索',
              onPressed: () => setState(() => _searchOpen = true),
            ),
            IconButton(
              icon: const Icon(Icons.folder_outlined),
              tooltip: '文件夹管理',
              onPressed: () => context.push('/treasure-spots/folders'),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          _FolderChipRow(),
          const Divider(height: 1),
          Expanded(child: _SpotListBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_treasure_spot',
        onPressed: () async {
          // 新建：extra 传 null，保存后通过 refresh token 自动刷新列表
          await context.push<bool>('/treasure-spots/edit', extra: null);
        },
        tooltip: '添加新地点',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _FolderChipRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(spotFolderListProvider);
    final filter = ref.watch(treasureSpotsFilterProvider);
    // 全部数量来自全部列表
    final allCountAsync = ref.watch(spotListProvider(null));

    final allCount = allCountAsync.valueOrNull?.length ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilterChip(
              label: Text('全部 $allCount'),
              selected: filter.folderId == null,
              onSelected: (_) {
                ref.read(treasureSpotsFilterProvider.notifier).state =
                    filter.copyWith(clearFolderId: true);
              },
            ),
            const SizedBox(width: 8),
            ...foldersAsync.when(
              loading: () => [
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
              error: (_, __) => const [],
              data: (folders) {
                return folders.map((f) {
                  // folderSpotCountProvider 现在是 FutureProvider，用 AsyncValue
                  final cntAsync = ref.watch(folderSpotCountProvider(f.id));
                  final cnt = cntAsync.valueOrNull ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      avatar: Icon(
                        f.iconData,
                        size: 16,
                        color: filter.folderId == f.id ? null : f.color,
                      ),
                      label: Text('${f.name} $cnt'),
                      selected: filter.folderId == f.id,
                      onSelected: (_) {
                        final next = filter.folderId == f.id
                            ? filter.copyWith(clearFolderId: true)
                            : filter.copyWith(folderId: f.id);
                        ref.read(treasureSpotsFilterProvider.notifier).state =
                            next;
                      },
                    ),
                  );
                }).toList();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotListBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(filteredTreasureSpotsProvider);
    return listAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败：$e')),
      data: (list) {
        if (list.isEmpty) {
          return _buildEmpty(context);
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _SpotCard(spot: list[i]),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.place_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          const Text(
            '还没收藏任何宝藏地点',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角 + 开始记录',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SpotCard extends ConsumerWidget {
  final TreasureSpot spot;

  const _SpotCard({required this.spot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // spot.type 现在是 String(sql 值)，用 infoOfKey 取得信息
    final typeInfo = PlaceTypeEnums.infoOfKey(spot.type);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          // 进入详情页；refresh token 机制无需手动 invalidate
          await context.push<bool>(
            '/treasure-spots/detail',
            extra: spot.id,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 首图或图标占位
            SizedBox(
              height: 140,
              width: double.infinity,
              child: spot.images.isNotEmpty
                  ? Image(
                      image: _imageProvider(spot.images.first),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _IconPlaceholder(
                          icon: typeInfo.icon, color: scheme.primary),
                    )
                  : _IconPlaceholder(
                      icon: typeInfo.icon,
                      color: scheme.primary,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          spot.name,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(typeInfo.icon,
                                size: 12, color: scheme.onPrimaryContainer),
                            const SizedBox(width: 4),
                            Text(
                              typeInfo.label,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (spot.address.isNotEmpty)
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            spot.address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  if (spot.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final t in spot.tags)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '#$t',
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  // 底部操作栏
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => launchNavigation(context, spot),
                          icon: const Icon(Icons.directions_walk),
                          label: const Text('去这里'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: '编辑',
                        onPressed: () async {
                          await context.push<bool>(
                            '/treasure-spots/edit',
                            extra: spot.id,
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red),
                        tooltip: '删除',
                        onPressed: () => _confirmDelete(context, ref),
                      ),
                    ],
                  ),
                ],
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

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
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
      // 使用 AsyncNotifier 删除；内部会 bump refresh token，列表自动刷新
      await ref.read(spotListNotifierProvider.notifier).deleteSpot(spot.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除')),
        );
      }
    }
  }
}

class _IconPlaceholder extends StatelessWidget {
  final IconData icon;
  final Color? color;

  const _IconPlaceholder({required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          icon,
          size: 60,
          color: color ?? scheme.primary,
        ),
      ),
    );
  }
}
