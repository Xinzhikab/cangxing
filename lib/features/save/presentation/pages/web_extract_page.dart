import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:fav_app/features/save/data/services/site_rule.dart';
import 'package:fav_app/features/settings/data/providers/cookie_provider.dart';

/// WebView 渲染提取到的结果：正文文本 + 图片地址列表 + 标题/作者/发布时间 + 提取日志。
class WebExtractResult {
  final String text;
  final List<String> images;
  final String author;
  final String publishedAt;
  final String title;
  final List<String> log;

  const WebExtractResult({
    required this.text,
    required this.images,
    this.author = '',
    this.publishedAt = '',
    this.title = '',
    this.log = const [],
  });

  WebExtractResult copyWith({
    String? text,
    List<String>? images,
    String? author,
    String? publishedAt,
    String? title,
    List<String>? log,
  }) {
    return WebExtractResult(
      text: text ?? this.text,
      images: images ?? this.images,
      author: author ?? this.author,
      publishedAt: publishedAt ?? this.publishedAt,
      title: title ?? this.title,
      log: log ?? this.log,
    );
  }
}

/// 无头 WebView 提取器：不打开任何提取页面，全程无画面。
///
/// 原理：在根 Overlay 挂一个屏幕外（负坐标）但保持真实尺寸的 WebView，
/// 页面照常布局、渲染、执行 JS（零尺寸/Offstage 会导致不加载），
/// 而用户屏幕上看不到任何提取画面。提取完成/失败后自动移除。
///
/// 适用于小黑盒等依赖 JS 渲染、原始 HTML 抓不到正文的站点。
class HeadlessWebExtractor {
  static int _activeInstances = 0;
  static const _maxActiveInstances = 2;

  HeadlessWebExtractor({
    required this.url,
    required this.cookies,
    this.hardTimeout = const Duration(seconds: 60),
  });

  final String url;
  final List<SiteCookie> cookies;

  /// 整体硬超时：无论如何都不能永久卡住保存流程。
  final Duration hardTimeout;

  late final WebViewController _controller;
  late final SiteRule _rule;
  final List<String> _log = [];
  OverlayEntry? _entry;
  Timer? _hardTimer;
  bool _done = false;
  final Completer<WebExtractResult?> _completer = Completer<WebExtractResult?>();
  bool _retriedNoImage = false;

  String? _jsTriggerLazyScroll;
  String? _jsTriggerLazySwiper;
  String? _jsTriggerLazyDots;
  String? _jsTriggerLazyDom;
  String? _jsHasContent;
  String? _jsExtract;

  void _addLog(String msg) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    _log.add('[$ts] $msg');
  }

  /// 从 assets 中加载所有 JS 脚本（只加载一次）。
  Future<void> _loadJsAssets() async {
    if (_jsExtract != null) return;
    _jsTriggerLazyScroll = await rootBundle.loadString('assets/extract/trigger_lazy_scroll.js');
    _jsTriggerLazySwiper = await rootBundle.loadString('assets/extract/trigger_lazy_swiper.js');
    _jsTriggerLazyDots = await rootBundle.loadString('assets/extract/trigger_lazy_dots.js');
    _jsTriggerLazyDom = await rootBundle.loadString('assets/extract/trigger_lazy_dom.js');
    _jsHasContent = await rootBundle.loadString('assets/extract/has_content.js');
    _jsExtract = await rootBundle.loadString('assets/extract/extract.js');
  }

  /// 启动后台提取。返回 null 表示提取失败（调用方降级为仅存原文/链接）。
  Future<WebExtractResult?> start(BuildContext context) async {
    if (_done) return _completer.future;
    _activeInstances++;
    _addLog('HeadlessWebExtractor 启动（当前活跃实例: $_activeInstances/$_maxActiveInstances）');
    // 先加载 JS assets，避免注入时为空
    try {
      await _loadJsAssets();
    } catch (e) {
      _addLog('JS assets 加载失败: $e');
      _finish(null);
      return _completer.future;
    }
    // 按 URL 域名匹配专属提取规则（小黑盒等），未命中走默认通用规则
    _rule = SiteRuleRegistry.ruleFor(url);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            _addLog('页面开始加载...');
          },
          onPageFinished: (_) {
            _addLog('页面加载完成');
            // 页面加载完成后正文可能懒加载，轮询：正文一出现立即提取
            _pollExtract();
          },
          onWebResourceError: (error) {
            // 只处理主框架加载错误；子资源（图片/脚本/CDN）加载失败不影响正文提取
            if (error.isForMainFrame != true) return;
            _addLog('页面加载错误: ${error.description} (code=${error.errorCode})');
            // 主框架网络类加载失败（如 DNS 解析失败）自动结束，保存流程降级
            if (_isNetworkError(error)) {
              _finish(null);
            }
          },
        ),
      );

    // 屏幕内 1x1 像素挂载：用 OverflowBox 保持真实渲染尺寸 412x915，
    // 配合 0.001 透明度，既不可见又不会被 OEM ROM 判定为离屏而暂停渲染。
    _entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 1,
                height: 1,
                child: OverflowBox(
                  minWidth: 412,
                  maxWidth: 412,
                  minHeight: 915,
                  maxHeight: 915,
                  child: IgnorePointer(
                    ignoring: true,
                    child: Opacity(
                      opacity: 0.001,
                      child: WebViewWidget(controller: _controller),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);

    // 硬超时兜底：任何环节卡死都在此强制结束
    _hardTimer = Timer(hardTimeout, () {
      _addLog('整体超时（${hardTimeout.inSeconds}s），终止提取');
      _finish(null);
    });

    _initWithCookie();
    return _completer.future;
  }

  static bool _shouldInjectCookie({
    required Uri pageUri,
    required SiteCookie cookie,
  }) {
    final pageHost = pageUri.host.toLowerCase();
    var cookieDomain = cookie.domain.toLowerCase().trim();
    if (cookieDomain.isEmpty) return false;
    cookieDomain = cookieDomain.replaceAll('www.', '');
    if (cookieDomain.isEmpty) return false;
    final exactMatch = cookieDomain == pageHost;
    final wildcardMatch = cookieDomain.startsWith('.') &&
        pageHost.endsWith(cookieDomain);
    bool match = exactMatch || wildcardMatch;
    if (match && !exactMatch && cookieDomain.length < 4) {
      match = false;
    }
    if (!match) {
      debugPrint('[Cookie] skip ${cookie.domain} for $pageHost');
    }
    return match;
  }

  /// 注入域名 Cookie（与 Dio 抓取一致），再加载页面。
  Future<void> _initWithCookie() async {
    _addLog('开始加载页面: $url');
    try {
      final pageUri = Uri.parse(url);
      final cookieManager = WebViewCookieManager();
      _addLog('配置的 Cookie 域名数: ${cookies.length}');
      for (final c in cookies) {
        if (!_shouldInjectCookie(pageUri: pageUri, cookie: c)) continue;
        var d = c.domain.toLowerCase().trim().replaceAll('www.', '');
        if (!d.startsWith('.')) d = '.$d';
        _addLog('注入 Cookie: 域名=$d');
        for (final pair in c.cookie.split(';')) {
          final p = pair.trim();
          if (p.isEmpty || !p.contains('=')) continue;
          final i = p.indexOf('=');
          await cookieManager.setCookie(
            WebViewCookie(
              name: p.substring(0, i).trim(),
              value: p.substring(i + 1).trim(),
              domain: d,
              path: '/',
            ),
          );
        }
      }
    } catch (e) {
      _addLog('Cookie 注入异常: $e');
    }
    if (!_done) {
      await _controller.loadRequest(Uri.parse(url));
    }
  }

  /// 外部取消转录：用户关闭页面时调用，避免资源泄漏。
  void cancel() {
    if (_done) return;
    _addLog('用户取消提取');
    _finish(null);
  }

  /// 结束提取：移除 Overlay、取消定时器、完成 Future（只执行一次）。
  void _finish(WebExtractResult? result) {
    if (_done) return;
    _done = true;
    _hardTimer?.cancel();
    _entry?.remove();
    _entry = null;
    try {
      unawaited(_controller.clearCache());
      unawaited(_controller.clearLocalStorage());
    } catch (_) {
      // 清理失败忽略，不影响主流程
    }
    if (_activeInstances > 0) _activeInstances--;
    _completer.complete(result?.copyWith(log: List.of(_log)));
  }

  Future<void> _pollExtract() async {
    if (_done) return;
    _addLog('页面加载完成，开始轮询正文...');
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!_done && DateTime.now().isBefore(deadline)) {
      // 正文一旦渲染出来（长度超过阈值）立即提取，加快小黑盒等懒加载页面
      if (await _hasContent()) {
        _addLog('正文已渲染，触发懒加载图片...');
        // 正文图片多为懒加载（滚动到视口才填充 src），先滚动触发加载，避免图片缺失
        await _triggerLazyImages();
        _addLog('懒加载触发完成，开始提取...');
        if (await _extract()) return;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (_done) return;
    // 超时兜底：先触发懒加载再提取——部分图集帖正文极短（如十几字的
    // 轮播帖），轮询阈值 50 字一直不满足而超时，但轮播图需要滑动才加载
    _addLog('轮询超时，触发懒加载后兜底提取...');
    await _triggerLazyImages();
    if (await _extract()) return;
    // 仍未提取到正文：等 5 秒再试最后一次（部分站点渲染极慢）
    await Future<void>.delayed(const Duration(seconds: 5));
    if (_done) return;
    _addLog('最终重试提取...');
    if (await _extract()) return;
    // 多次提取失败：结束提取，保存流程降级为仅存原文/链接，避免卡死
    _addLog('多次提取失败，终止提取（降级保存）');
    _finish(null);
  }

  /// 触发懒加载图片加载：包括垂直滚动（正文内图）和水平滑动轮播（swiper）。
  /// 轮播图在 Android WebView 中仅当前活动页的 img 有 src，
  /// 需要手动滑过每一页才能触发其余图片加载。
  /// 采用多重 fallback 策略：Swiper API → 导航点点击 → 直接操作 DOM。
  Future<void> _triggerLazyImages() async {
    try {
      // 垂直滚动：触发正文内懒加载图片
      _addLog('垂直滚动触发懒加载...');
      await _controller.runJavaScript(_jsTriggerLazyScroll!);
      await Future<void>.delayed(const Duration(milliseconds: 800));

      // 策略 1：尝试 Swiper API 滑动轮播
      _addLog('尝试 Swiper API 滑动轮播...');
      final swiperResult = await _controller.runJavaScriptReturningResult(_jsTriggerLazySwiper!);
      _addLog('Swiper API 结果: $swiperResult');

      // 策略 2：尝试点击轮播导航点（.swiper-pagination-bullet 等）
      _addLog('尝试点击轮播导航点...');
      final dotResult = await _controller.runJavaScriptReturningResult(_jsTriggerLazyDots!);
      _addLog('导航点点击结果: $dotResult');

      // 策略 3：直接操作 DOM，强制让每个轮播项可见并触发图片加载
      _addLog('尝试 DOM 直接操作轮播项...');
      final domResult = await _controller.runJavaScriptReturningResult(_jsTriggerLazyDom!);
      _addLog('DOM 操作结果: $domResult');

      // 等所有轮播图滑过 + 图片请求完成
      int prevCount = 0;
      int equalCount = 0;
      const maxTotalWaitMs = 3500;
      const pollIntervalMs = 300;
      int waited = 0;
      while (waited < maxTotalWaitMs) {
        await Future<void>.delayed(const Duration(milliseconds: pollIntervalMs));
        waited += pollIntervalMs;
        final cur = int.tryParse(await _controller.runJavaScriptReturningResult(
          "(function(){return Array.from(document.querySelectorAll('img')).filter(function(i){return i.src && i.src.length>4}).length})()"
        ).toString() ?? '0') ?? 0;
        if (cur == prevCount) {
          equalCount++;
          if (equalCount >= 2) break;
        } else {
          equalCount = 0;
        }
        prevCount = cur;
      }
    } catch (e) {
      _addLog('懒加载触发异常: $e');
      // 滚动/滑动失败不影响后续提取
    }
  }

  /// 按站点规则生成正文容器的 JS 选择器链（含兜底 body）。
  String get _selectorChainJs {
    final chain = _rule.contentSelectors
        .map((s) => 'document.querySelector("${s.replaceAll('"', r'\"')}")')
        .join('\n            || ');
    return '$chain\n            || document.body';
  }

  /// 检查正文容器是否已渲染出内容。
  /// 正文 > 50 字即就绪；或正文非空且页面已有轮播组件（图集帖正文
  /// 可能只有十几个字，照片全在 JS 渲染的轮播里，如小黑盒图集帖）。
  Future<bool> _hasContent() async {
    try {
      final js = _jsHasContent!.replaceAll('/*__SELECTOR_CHAIN__*/', _selectorChainJs);
      final raw = await _controller.runJavaScriptReturningResult(js);
      return raw.toString().replaceAll('"', '').trim() == '1';
    } catch (e) {
      _addLog('JS 提取异常: $e');
      return false;
    }
  }

  /// 判断是否为网络类加载失败（DNS 解析失败、无网络、连接/超时等）。
  static bool _isNetworkError(WebResourceError error) {
    final desc = error.description.toLowerCase();
    if (desc.contains('err_name_not_resolved') ||
        desc.contains('err_internet_disconnected') ||
        desc.contains('err_connection') ||
        desc.contains('err_timed_out') ||
        desc.contains('offline') ||
        desc.contains('host lookup') ||
        desc.contains('network error')) {
      return true;
    }
    // Android WebView 网络类错误码
    const networkCodes = {-2, -3, -6, -7, -8, -10, -11, -12, -14};
    return networkCodes.contains(error.errorCode);
  }

  /// 注入 JS 提取可见正文与图片。
  /// 返回是否提取成功（正文非空），供自动流程决定重试/降级。
  Future<bool> _extract() async {
    if (_done) return false;
    // 去掉脚本/样式/导航/评论区等，取正文容器；取不到就退回 body。
    final bannedClasses = jsonEncode(_rule.bannedClassParts);
    final bannedUrls = jsonEncode(_rule.bannedUrlParts);
    final js = _jsExtract!
        .replaceAll('/*__BANNED_CLASSES__*/', bannedClasses)
        .replaceAll('/*__BANNED_URLS__*/', bannedUrls)
        .replaceAll('/*__SELECTOR_CHAIN__*/', _selectorChainJs);
    try {
      final raw = await _controller.runJavaScriptReturningResult(js);
      final result = _parseResult(raw);
      _addLog('提取结果: 正文长度=${result.text.length} | 图片=${result.images.length}张 | 标题=${result.title} | 作者=${result.author}');
      if (result.images.isNotEmpty) {
        _addLog('图片URL: ${result.images.take(5).join(' | ')}${result.images.length > 5 ? ' ...' : ''}');
      }
      if (result.text.trim().isNotEmpty) {
        // 首次提取没有图片时，轮播/懒加载图尚未就绪：
        // 再触发一轮懒加载（滑动轮播）后重试一次
        if (result.images.isEmpty && !_retriedNoImage) {
          _addLog('首次提取无图片，触发懒加载后重试...');
          _retriedNoImage = true;
          await _triggerLazyImages();
          return await _extract();
        }
        _finish(result);
        return true;
      } else {
        _addLog('提取失败: 正文为空');
      }
    } catch (e) {
      _addLog('提取异常: $e');
      // 提取失败不阻断，由自动流程决定重试/降级
    }
    return false;
  }

  /// `runJavaScriptReturningResult` 返回值是 JSON 编码字符串；JS 又返回了
  /// 一个 JSON 字符串，因此需要解码两层得到 {text, images}。
  WebExtractResult _parseResult(Object? raw) {
    try {
      final first = jsonDecode(raw.toString());
      final map = first is String ? jsonDecode(first) : first;
      if (map is Map) {
        return WebExtractResult(
          text: (map['text'] as String? ?? '').trim(),
          images: (map['images'] as List? ?? const [])
              .whereType<String>()
              .where((u) => u.trim().isNotEmpty)
              .toList(growable: false),
          author: (map['author'] as String? ?? '').trim(),
          publishedAt: (map['publishedAt'] as String? ?? '').trim(),
          title: (map['title'] as String? ?? '').trim(),
        );
      }
    } catch (e, st) {
      debugPrint('解析结果异常: $e\n$st');
    }
    return const WebExtractResult(text: '', images: []);
  }
}
