import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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

  void _addLog(String msg) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    _log.add('[$ts] $msg');
  }

  /// 启动后台提取。返回 null 表示提取失败（调用方降级为仅存原文/链接）。
  Future<WebExtractResult?> start(BuildContext context) {
    if (_done) return _completer.future;
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

    // 屏幕外挂载：真实尺寸保证页面正常渲染执行 JS，负坐标移出可视区
    _entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -10000,
        top: -10000,
        width: 412,
        height: 915,
        child: IgnorePointer(child: WebViewWidget(controller: _controller)),
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

  /// 注入域名 Cookie（与 Dio 抓取一致），再加载页面。
  Future<void> _initWithCookie() async {
    _addLog('开始加载页面: $url');
    try {
      final host = Uri.parse(url).host.toLowerCase();
      final cookieManager = WebViewCookieManager();
      _addLog('配置的 Cookie 域名数: ${cookies.length}');
      for (final c in cookies) {
        final d = c.domain.toLowerCase().trim().replaceAll('www.', '');
        if (d.isEmpty || !host.contains(d)) continue;
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

  /// 结束提取：移除 Overlay、取消定时器、完成 Future（只执行一次）。
  void _finish(WebExtractResult? result) {
    if (_done) return;
    _done = true;
    _hardTimer?.cancel();
    _entry?.remove();
    _entry = null;
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
      await _controller.runJavaScript('''
        (function() {
          var h = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
          var y = 0;
          var step = Math.max(200, Math.floor(h / 10));
          var timer = setInterval(function() {
            y += step;
            if (y >= h) {
              clearInterval(timer);
              window.scrollTo(0, 0);
            } else {
              window.scrollTo(0, y);
            }
          }, 100);
        })()
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 800));

      // 策略 1：尝试 Swiper API 滑动轮播
      _addLog('尝试 Swiper API 滑动轮播...');
      final swiperResult = await _controller.runJavaScriptReturningResult('''
        (function() {
          // 尝试多个可能的轮播选择器
          var selectors = ['.swiper-initialized', '.swiper', '.swiper-container', '[class*="swiper"]', '[class*="carousel"]', '[class*="banner"]', '[class*="slider"]', '.header-image'];
          var swiperEl = null;
          for (var i = 0; i < selectors.length; i++) {
            swiperEl = document.querySelector(selectors[i]);
            if (swiperEl && swiperEl.swiper) break;
            swiperEl = null;
          }
          if (!swiperEl || !swiperEl.swiper) return 'no_swiper';
          var sw = swiperEl.swiper;
          var count = sw.slides ? sw.slides.length : 0;
          if (count <= 1) return 'single_slide';
          var i = 0;
          var timer = setInterval(function() {
            i++;
            if (i >= count) {
              clearInterval(timer);
              sw.slideTo(0, 0);
            } else {
              sw.slideTo(i, 300);
            }
          }, 600);
          return 'swiper_ok:' + count;
        })()
      ''');
      _addLog('Swiper API 结果: $swiperResult');

      // 策略 2：尝试点击轮播导航点（.swiper-pagination-bullet 等）
      _addLog('尝试点击轮播导航点...');
      final dotResult = await _controller.runJavaScriptReturningResult('''
        (function() {
          var dotSelectors = ['.swiper-pagination-bullet', '[class*="pagination"] [class*="dot"]', '[class*="pagination"] [class*="bullet"]', '[class*="indicator"] [class*="dot"]', '[class*="carousel"] [class*="dot"]', '.header-image [class*="dot"]', '[class*="banner"] [class*="dot"]'];
          var dots = null;
          for (var i = 0; i < dotSelectors.length; i++) {
            dots = document.querySelectorAll(dotSelectors[i]);
            if (dots.length > 1) break;
            dots = null;
          }
          if (!dots || dots.length <= 1) return 'no_dots';
          for (var i = 0; i < dots.length; i++) {
            dots[i].click();
          }
          return 'dots_ok:' + dots.length;
        })()
      ''');
      _addLog('导航点点击结果: $dotResult');

      // 策略 3：直接操作 DOM，强制让每个轮播项可见并触发图片加载
      _addLog('尝试 DOM 直接操作轮播项...');
      final domResult = await _controller.runJavaScriptReturningResult('''
        (function() {
          // 尝试多种可能的轮播项选择器
          var itemSelectors = ['.header-image__item', '.swiper-slide', '[class*="carousel"] [class*="item"]', '[class*="banner"] [class*="item"]', '[class*="slider"] [class*="item"]'];
          var items = null;
          for (var i = 0; i < itemSelectors.length; i++) {
            items = document.querySelectorAll(itemSelectors[i]);
            if (items.length > 1) break;
            items = null;
          }
          if (!items || items.length <= 1) return 'no_items';
          // 常见的懒加载图片属性，按优先级尝试
          var attrList = ['data-src', 'data-original', 'data-lazy-src', 'data-url', 'data-image', 'data-bg', 'data-background', 'data-thumb', 'data-lazy'];
          var loaded = 0;
          var imgCount = 0;
          var bgCount = 0;
          // 读取元素（含 CSS 类定义）的 background-image，返回 url(...) 内的地址
          function bgOf(el) {
            try {
              var cs = getComputedStyle(el);
              var m = (cs.backgroundImage || '').match(/url\\(["']?([^"'\\)]+)["']?\\)/);
              return m && m[1] ? m[1] : '';
            } catch (e) { return ''; }
          }
          for (var i = 0; i < items.length; i++) {
            items[i].style.display = 'block';
            items[i].style.visibility = 'visible';
            items[i].style.opacity = '1';
            items[i].style.transform = 'translateX(0)';
            items[i].style.position = 'static';
            var imgs = items[i].querySelectorAll('img');
            imgCount += imgs.length;
            // 轮播项自身或其后代可能是 background-image（无 img 标签）
            var bgs = [];
            var selfBg = bgOf(items[i]);
            if (selfBg && selfBg.indexOf('data:') !== 0) bgs.push(selfBg);
            var bgEls = items[i].querySelectorAll('*');
            for (var bi = 0; bi < bgEls.length; bi++) {
              var b = bgOf(bgEls[bi]);
              if (b && b.indexOf('data:') !== 0 && b.indexOf('blob:') !== 0) bgs.push(b);
            }
            if (bgs.length && imgs.length === 0) {
              // 无 img 标签但 CSS 有背景图：用第一个背景图填充占位 img
              var phImg = document.createElement('img');
              phImg.setAttribute('src', bgs[0]);
              phImg.setAttribute('data-real-bg', bgs.join(','));
              items[i].appendChild(phImg);
              loaded++;
            }
            bgCount += bgs.length;
            for (var j = 0; j < imgs.length; j++) {
              var realSrc = '';
              for (var k = 0; k < attrList.length; k++) {
                var v = imgs[j].getAttribute(attrList[k]);
                if (v && v.indexOf('data:') !== 0 && v.indexOf('blob:') !== 0) { realSrc = v; break; }
              }
              if (!realSrc) realSrc = imgs[j].getAttribute('src') || '';
              if (!realSrc) {
                var b2 = bgOf(imgs[j]);
                if (!b2 && imgs[j].parentNode) b2 = bgOf(imgs[j].parentNode);
                if (b2 && b2.indexOf('data:') !== 0) realSrc = b2;
              }
              if (realSrc) {
                imgs[j].setAttribute('src', realSrc);
                loaded++;
              }
            }
          }
          return 'dom_ok:' + items.length + '_imgs:' + imgCount + '_bg:' + bgCount + '_loaded:' + loaded + '_sample:' + items[0].outerHTML.replace(/\\s+/g, ' ').substring(0, 200);
        })()
      ''');
      _addLog('DOM 操作结果: $domResult');

      // 等所有轮播图滑过 + 图片请求完成
      await Future<void>.delayed(const Duration(milliseconds: 3500));
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
      final js = '''
        (function() {
          var el = $_selectorChainJs;
          if (!el) return '0';
          var len = (el.innerText || el.textContent || '').trim().length;
          if (len > 50) return '1';
          if (len < 5) return '0';
          var carousel = document.querySelectorAll('.swiper-slide, .header-image__item, [class*="slider"] [class*="item"], [class*="carousel"] [class*="item"]').length;
          return carousel > 1 ? '1' : '0';
        })()
      ''';
      final raw = await _controller.runJavaScriptReturningResult(js);
      return raw.toString().replaceAll('"', '').trim() == '1';
    } catch (_) {
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
    final js = '''
      (function() {
        // 过滤头像/图标/表情等与正文无关的图片
        function relevant(img) {
          var cls = ((img.className || '') + ' ' + (img.id || '')).toLowerCase();
          var banned = $bannedClasses;
          for (var i = 0; i < banned.length; i++) {
            if (cls.indexOf(banned[i]) !== -1) return false;
          }
          var w = parseInt(img.getAttribute('width'), 10);
          if (w && w < 40) return false;
          return true;
        }
        // 过滤 URL 命中站点规则排除路径的图片（如 /avatar/、/emoji/）
        function bannedUrl(src) {
          var s = src.toLowerCase();
          var banned = $bannedUrls;
          for (var i = 0; i < banned.length; i++) {
            if (s.indexOf(banned[i]) !== -1) return true;
          }
          return false;
        }
        var el = $_selectorChainJs;
        if (!el) return JSON.stringify({text:'', images:[]});
        // 在同一个克隆副本上生成正文与图片列表，保证 [图N] 占位符和 images 一一对应：
        // 先移除评论区/导航等容器，它们的图片不会进入任何一方，避免数量错位
        var c = el.cloneNode(true);
        var tags = ['script','style','noscript','iframe','svg','nav','header','footer','aside'];
        c.querySelectorAll(tags.join(',')).forEach(function(n){ n.remove(); });
        c.querySelectorAll('[class*="comment"],[id*="comment"]').forEach(function(n){ n.remove(); });
        var images = [];
        var seen = {};
        var idx = 0;
        function pushImg(img) {
          // 支持多种懒加载属性：data-src, data-original, data-lazy-src, data-url, data-image, data-bg 等
          var attrList = ['data-src', 'data-original', 'data-lazy-src', 'data-url', 'data-image', 'data-bg', 'data-background', 'data-thumb', 'data-lazy'];
          var src = '';
          for (var k = 0; k < attrList.length; k++) {
            var v = img.getAttribute(attrList[k]);
            if (v && v.indexOf('data:') !== 0 && v.indexOf('blob:') !== 0) { src = v; break; }
          }
          if (!src) src = img.getAttribute('src') || '';
          if (!src) {
            // 兜底：用 getComputedStyle 从 img 或其父元素读取 CSS 定义的 background-image
            try {
              var cs = getComputedStyle(img);
              var m = (cs.backgroundImage || '').match(/url\\(["']?([^"'\\)]+)["']?\\)/);
              if (m && m[1] && m[1].indexOf('data:') !== 0) { src = m[1]; }
              if (!src && img.parentNode) {
                var cs2 = getComputedStyle(img.parentNode);
                var m2 = (cs2.backgroundImage || '').match(/url\\(["']?([^"'\\)]+)["']?\\)/);
                if (m2 && m2[1] && m2[1].indexOf('data:') !== 0) { src = m2[1]; }
              }
            } catch (e) {}
          }
          if (!src || src.indexOf('data:') === 0 || src.indexOf('blob:') === 0) return false;
          if (!relevant(img) || bannedUrl(src) || seen[src]) return false;
          seen[src] = 1;
          idx++;
          images.push(src);
          return true;
        }
        // 首图轮播（.header-image__item / .swiper-slide 等）先入图列表，并把 [图N] 占位符插到正文开头
        // 轮播项 class 因站点而异（小黑盒为 .swiper-slide + .bbs-link-img-slider-slide），
        // 用多重选择器匹配，与 _triggerLazyImages 的 DOM 策略保持一致
        var headerSelectors = ['.header-image__item', '.swiper-slide', '[class*="carousel"] [class*="item"]', '[class*="banner"] [class*="item"]', '[class*="slider"] [class*="item"]'];
        var headerItems = null;
        for (var hs = 0; hs < headerSelectors.length; hs++) {
          var hq = document.querySelectorAll(headerSelectors[hs]);
          if (hq.length > 1) { headerItems = hq; break; }
        }
        var headerPhs = [];
        if (headerItems) {
          for (var hi = 0; hi < headerItems.length; hi++) {
          var itemImgs = headerItems[hi].querySelectorAll('img');
          if (itemImgs.length) {
            for (var ii = 0; ii < itemImgs.length; ii++) {
              if (pushImg(itemImgs[ii])) headerPhs.push(document.createTextNode('[图' + idx + ']'));
            }
          } else {
            // 轮播项无 img 标签时，用 getComputedStyle 读取 CSS 类/内联 background-image
            var bgSrc = '';
            try {
              var cs0 = getComputedStyle(headerItems[hi]);
              var m0 = (cs0.backgroundImage || '').match(/url\\(["']?([^"'\\)]+)["']?\\)/);
              if (m0 && m0[1]) bgSrc = m0[1];
              if (!bgSrc) {
                var bgEls2 = headerItems[hi].querySelectorAll('*');
                for (var bi2 = 0; bi2 < bgEls2.length && !bgSrc; bi2++) {
                  var cs2 = getComputedStyle(bgEls2[bi2]);
                  var m2 = (cs2.backgroundImage || '').match(/url\\(["']?([^"'\\)]+)["']?\\)/);
                  if (m2 && m2[1] && m2[1].indexOf('data:') !== 0) bgSrc = m2[1];
                }
              }
            } catch (e) {}
            if (bgSrc && bgSrc.indexOf('data:') !== 0 &&
                !bannedUrl(bgSrc) && !seen[bgSrc]) {
              seen[bgSrc] = 1;
              idx++;
              images.push(bgSrc);
              headerPhs.push(document.createTextNode('[图' + idx + ']'));
            }
          }
          }
        }
        if (headerPhs.length && c.firstChild) {
          var frag = document.createDocumentFragment();
          for (var k = 0; k < headerPhs.length; k++) frag.appendChild(headerPhs[k]);
          c.insertBefore(frag, c.firstChild);
        }
        // 正文容器内的图片继续编号并原位替换为占位符
        var imgs = c.querySelectorAll('img');
        for (var j = 0; j < imgs.length; j++) {
          if (pushImg(imgs[j])) {
            var ph = document.createTextNode('[图' + idx + ']');
            if (imgs[j].parentNode) imgs[j].parentNode.replaceChild(ph, imgs[j]);
          }
        }
        // 提取正文并保留换行。注意：c 是 cloneNode 的副本，不在文档流
        // 中，innerText 对 detached 节点会回退为 textContent（纯拼接、
        // 无换行），所以必须自己按 DOM 遍历，在块级元素边界补换行
        var blockTags = ['p','div','section','article','header','footer','nav','aside','li','ul','ol','dl','dt','dd','h1','h2','h3','h4','h5','h6','pre','table','tr','figure','figcaption'];
        function blockText(node) {
          if (node.nodeType === 3) return node.textContent;
          if (node.nodeType !== 1) return '';
          var tag = node.tagName.toLowerCase();
          if (tag === 'br') return '\\n';
          if (['script','style','noscript','iframe','svg'].indexOf(tag) >= 0) return '';
          // 行内粗体（b/strong）转 Markdown **粗体**
          if (tag === 'b' || tag === 'strong') {
            var bs = '';
            for (var bi = 0; bi < node.childNodes.length; bi++) {
              bs += blockText(node.childNodes[bi]);
            }
            bs = bs.trim();
            if (!bs) return '';
            return '**' + bs + '**';
          }
          var s = '';
          for (var i = 0; i < node.childNodes.length; i++) {
            s += blockText(node.childNodes[i]);
          }
          // blockquote 与正文区分：内部段落归一为行，逐行加 > 前缀，
          // 输出 Markdown 引用块（嵌套引用自然形成 > > 前缀）
          if (tag === 'blockquote') {
            var inner = s.replace(/[ \\t\\r]+/g, ' ')
              .replace(/ *\\n */g, '\\n')
              .replace(/\\n+/g, '\\n')
              .trim();
            if (!inner) return '\\n';
            var quoted = inner.split('\\n').map(function(l) { return '> ' + l; }).join('\\n');
            return '\\n' + quoted + '\\n';
          }
          if (blockTags.indexOf(tag) >= 0) s = '\\n' + s + '\\n';
          return s;
        }
        var t = blockText(c).trim()
          .replace(/[ \\t\\r]+/g, ' ')
          .replace(/ *\\n */g, '\\n')
          .replace(/\\n+/g, '\\n\\n');
        // 标题/作者/发布时间：小黑盒详情页有精确元素，优先取；其余站点走兜底
        var title = '';
        var author = '';
        var publishedAt = '';
        // 标题多重兜底：精确选择器 → og:title → h1 → document.title
        var titleSels = ['.section-title__content', '[class*="bbs-link"] [class*="title"]', 'h1.title', 'h1', '[class*="article-title"]', '[class*="post-title"]'];
        for (var ts = 0; ts < titleSels.length && !title; ts++) {
          var tEl = document.querySelector(titleSels[ts]);
          if (tEl) {
            var tT = (tEl.innerText || '').trim();
            if (tT && tT.length <= 120) title = tT;
          }
        }
        if (!title) {
          var og = document.querySelector('meta[property="og:title"]') || document.querySelector('meta[name="og:title"]');
          if (og) title = (og.getAttribute('content') || '').trim();
        }
        if (!title) title = (document.title || '').trim();
        // 最后兜底：纯图轮播帖无标题元素时，用正文第一句（去掉图片占位符）当标题
        if (!title) {
          var textOnly = t.replace(/\\[图\\d+\\]/g, '').trim();
          var m5 = textOnly.match(/^[^。！？!?~～]{4,40}/);
          if (m5) title = m5[0].trim();
        }
        // 去掉站点名后缀（如「xxx - 小黑盒」「xxx_小黑盒」）
        title = title.replace(/[\\s\\-_]+(小黑盒|酷安|哔哩哔哩|bilibili|微博|贴吧|抖音)\\s*\$/, '').trim();
        var authorEl = document.querySelector('.link-user__username');
        if (authorEl) author = (authorEl.innerText || '').trim();
        var dateEl = document.querySelector('.link-data__time');
        dateEl = dateEl || document.querySelector('.user-info__line-2');
        if (dateEl) {
          var dm = (dateEl.innerText || '').match(/(\\d{4}-\\d{2}-\\d{2}|\\d{2}-\\d{2})/);
          if (dm) publishedAt = dm[1];
        }
        // 兜底：作者卡片/元信息容器（小黑盒为 .link-user__user-wrapper），优先取它
        var metaText = '';
        var metaSels = ['[class*="link-user__user-wrapper"]','[class*="user-wrapper"]','[class*="user-info"]','[class*="author-info"]','[class*="user-card"]','[class*="post-meta"]','[class*="article-meta"]'];
        for (var i = 0; i < metaSels.length; i++) {
          var mEl = document.querySelector(metaSels[i]);
          if (mEl) { var mT = (mEl.innerText || '').trim(); if (mT && mT.length < 80) { metaText = mT; break; } }
        }
        if (metaText) {
          var mline = metaText.split('\\n').map(function(s){ return s.trim(); }).filter(function(s){ return s; });
          if (!author && mline.length && mline[0].length < 30 && !/^Lv\\.?\\s*\\d/i.test(mline[0]) && mline[0].indexOf('关注') < 0) {
            author = mline[0];
          }
          if (!publishedAt) {
            var dm2 = metaText.match(/(\\d{4}-\\d{2}-\\d{2}|\\d{2}-\\d{2})/);
            if (dm2) publishedAt = dm2[1];
          }
        }
        // 兜底：小黑盒作者名与 Lv.NN 分属两行，找到 Lv 行后向上回溯最近的单行昵称
        if (!author) {
          var lines = (document.body.innerText || '').split('\\n').map(function(s){ return s.trim(); }).filter(function(s){ return s; });
          for (var i = 0; i < lines.length; i++) {
            if (/^Lv\\.?\\s*\\d+/i.test(lines[i])) {
              for (var j = i - 1; j >= 0 && i - j <= 4; j--) {
                if (/^[A-Za-z0-9_\\-\\u4e00-\\u9fa5]{1,30}\$/.test(lines[j])) {
                  author = lines[j];
                  break;
                }
              }
              break;
            }
          }
        }
        if (!publishedAt) {
          var tm = (document.body.innerText || '').match(/Lv\\.?\\s*\\d+\\s*(\\d{4}-\\d{2}-\\d{2}|\\d{2}-\\d{2})/);
          if (tm) publishedAt = tm[1];
        }
        return JSON.stringify({text: t, images: images, author: author, publishedAt: publishedAt, title: title});
      })()
    ''';
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
    } catch (_) {}
    return const WebExtractResult(text: '', images: []);
  }
}
