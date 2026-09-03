import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageGalleryViewer extends StatefulWidget {
  final List<String> imagePaths;
  final int initialIndex;
  final String rootDir;

  const ImageGalleryViewer({
    super.key,
    required this.imagePaths,
    this.initialIndex = 0,
    required this.rootDir,
  });

  @override
  State<ImageGalleryViewer> createState() => _ImageGalleryViewerState();
}

class _ImageGalleryViewerState extends State<ImageGalleryViewer>
    with TickerProviderStateMixin {
  late final PageController _pageCtrl;
  late int _currentIndex;
  final Map<int, TransformationController> _transformCtrls = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
    _pageCtrl.addListener(() {
      final next = _pageCtrl.page?.round() ?? 0;
      if (next != _currentIndex) {
        setState(() => _currentIndex = next);
      }
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    for (final tc in _transformCtrls.values) {
      tc.dispose();
    }
    super.dispose();
  }

  TransformationController _tcFor(int index) {
    if (!_transformCtrls.containsKey(index)) {
      _transformCtrls[index] = TransformationController();
    }
    return _transformCtrls[index]!;
  }

  void _toggleZoom(int index, Offset tapPosition) {
    final tc = _tcFor(index);
    // 从矩阵中取出当前 x 方向缩放因子；若 < 1.5 视为未放大，双击则放大；否则还原
    final currentScale = tc.value.getMaxScaleOnAxis();
    final toZoomed = currentScale < 1.5;
    final end = Matrix4.identity();
    if (toZoomed) {
      // 以双击点为中心放大到 2.5x
      end.translate(
        -tapPosition.dx * (2.5 - 1),
        -tapPosition.dy * (2.5 - 1),
      );
      end.scale(2.5);
    }
    _animateTo(tc, end);
  }

  void _animateTo(TransformationController tc, Matrix4 end) {
    final start = tc.value.clone();
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    final anim = Matrix4Tween(begin: start, end: end).animate(
      CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic),
    );
    anim.addListener(() {
      tc.value = anim.value;
    });
    ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) ctrl.dispose();
    });
    ctrl.forward();
  }

  String _resolveFullPath(String raw) {
    if (raw.startsWith('http')) return raw;
    return p.join(widget.rootDir, raw);
  }

  bool _isNetwork(String raw) => raw.startsWith('http');

  Future<void> _onLongPress(int index) async {
    final messenger = ScaffoldMessenger.of(context);
    final choose = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.save_alt_rounded),
              title: const Text('保存到相册'),
              subtitle: const Text('保存到 App 文档目录/SavedImages，'
                  '请自行从系统相册导入'),
              onTap: () => Navigator.pop(ctx, 'save'),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
    if (choose != 'save') return;

    try {
      final raw = widget.imagePaths[index];
      final docDir = await getApplicationDocumentsDirectory();
      final saveDir = Directory(p.join(docDir.path, 'SavedImages'));
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }
      String finalPath;
      if (_isNetwork(raw)) {
        final name = p.basename(Uri.parse(raw).path);
        final safeName = name.isEmpty ? 'img_${DateTime.now().millisecondsSinceEpoch}.jpg' : name;
        finalPath = p.join(saveDir.path, safeName);
        final dio = Dio();
        await dio.download(raw, finalPath);
      } else {
        final srcPath = _resolveFullPath(raw);
        final name = p.basename(srcPath);
        finalPath = p.join(saveDir.path, name);
        final src = File(srcPath);
        await src.copy(finalPath);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('已保存到 App 文档目录/SavedImages：${p.basename(finalPath)}'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('保存失败：$e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '${_currentIndex + 1}/${widget.imagePaths.length}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          // 黑色背景点击空白处关闭
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: const SizedBox.expand(),
            ),
          ),
          PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.imagePaths.length,
            itemBuilder: (context, index) {
              final raw = widget.imagePaths[index];
              final tc = _tcFor(index);
              final isNet = _isNetwork(raw);
              final fullPath = isNet ? raw : _resolveFullPath(raw);
              Widget child;
              if (isNet) {
                child = Image.network(
                  fullPath,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(Icons.broken_image,
                        color: scheme.error, size: 64),
                  ),
                );
              } else {
                child = Image.file(
                  File(fullPath),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(Icons.broken_image,
                        color: scheme.error, size: 64),
                  ),
                );
              }
              return Center(
                child: SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: InteractiveViewer(
                    transformationController: tc,
                    maxScale: 5,
                    minScale: 0.5,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // 阻止空白背景的 onTap 冒泡
                      onTap: () {},
                      onDoubleTapDown: (details) =>
                          _toggleZoom(index, details.localPosition),
                      onLongPress: () => _onLongPress(index),
                      child: Center(child: child),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
