import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:fav_app/features/save/data/models/transcription_models.dart';
import 'package:fav_app/features/save/data/services/site_rule.dart';

/// 抓取到的网页内容：正文文本（含 [图N] 占位符）+ 图片地址列表。
/// 占位符顺序与 images 一一对应，AI 排版后替换为本地路径即可还原图片位置。
class FetchedContent {
  final String text;
  final List<String> images;
  final String author;
  final String publishedAt;

  const FetchedContent({
    required this.text,
    required this.images,
    this.author = '',
    this.publishedAt = '',
  });
}

class WebContentFetcher {
  final Dio dio;
  final String? Function(String url) cookieResolver;

  WebContentFetcher(this.dio, this.cookieResolver);

  static bool isLikelyUrl(String input) {
    final urlRegex = RegExp(
      r'^https?://',
      caseSensitive: false,
    );
    return urlRegex.hasMatch(input.trim());
  }

  Future<FetchedContent> fetch(String url) async {
    try {
      final Map<String, dynamic> headers = {
        // 模拟浏览器请求，避免部分站点（如小黑盒）对无 UA 请求返回 404/403
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      };
      final c = cookieResolver(url);
      if (c != null && c.isNotEmpty) {
        headers['Cookie'] = c;
      }
      final response = await dio.get<String>(
        url,
        options: Options(
          headers: headers,
          // 不自动抛 4xx/5xx，交由下方逻辑统一处理
          validateStatus: (_) => true,
        ),
      );
      if (response.statusCode == null ||
          response.statusCode! >= 400 ||
          response.data == null) {
        throw TranscriptionException(
          TranscriptionFailureReason.network,
          'HTTP ${response.statusCode}',
        );
      }
      final html = response.data!;
      final document = html_parser.parse(html);
      // 移除无关节点，避免把脚本/样式/导航抓成正文
      for (final tag in ['script', 'style', 'noscript', 'iframe', 'svg']) {
        for (final el in document.querySelectorAll(tag)) {
          el.remove();
        }
      }
      // 按域名取专属规则（小黑盒等），未命中走默认通用规则
      final rule = SiteRuleRegistry.ruleFor(url);
      dynamic element;
      for (final selector in rule.contentSelectors) {
        try {
          element = document.querySelector(selector);
          if (element != null && _visibleText(element).isNotEmpty) break;
        } catch (_) {}
      }
      element ??= document.body;
      if (element == null) {
        throw TranscriptionException(
          TranscriptionFailureReason.network,
          'Empty page body',
        );
      }
      final text = _visibleText(element);
      if (text.trim().isEmpty) {
        throw TranscriptionException(
          TranscriptionFailureReason.network,
          '页面没有可提取的正文内容',
        );
      }
      return FetchedContent(
        // 带 [图N] 占位符的正文，供 AI 排版后替换为本地图片路径
        text: _visibleTextWithPlaceholders(url, element, rule),
        images: _collectImages(url, element, rule),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        throw TranscriptionException(TranscriptionFailureReason.network, 'Timeout');
      }
      throw TranscriptionException(
        TranscriptionFailureReason.network,
        e.message ?? 'Network error',
      );
    } on TranscriptionException {
      rethrow;
    } catch (e) {
      throw TranscriptionException(
        TranscriptionFailureReason.network,
        e.toString(),
      );
    }
  }

  /// 提取元素的可见文本：剔除 script/style 后代并压缩空白。
  static String _visibleText(dom.Element el) {
    final clone = el.clone(true);
    for (final tag in ['script', 'style', 'noscript', 'iframe']) {
      for (final s in clone.querySelectorAll(tag)) {
        s.remove();
      }
    }
    final raw = _blockAwareText(clone);
    return _normalizeText(raw);
  }

  /// 块级感知文本提取：HTML 解析器的 Element.text 只拼接文本节点，
  /// 不会在块级元素边界产生换行（整篇变一行）。这里按 DOM 遍历，
  /// 块级标签（p/div/li/h1-h6 等）边界补换行，<br> 视为换行。
  static const Set<String> _blockTags = {
    'p', 'div', 'section', 'article', 'header', 'footer', 'nav', 'aside',
    'li', 'ul', 'ol', 'dl', 'dt', 'dd',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'blockquote', 'pre', 'table', 'tr', 'figure', 'figcaption', 'hr',
  };

  static String _blockAwareText(dom.Node node) {
    if (node is dom.Text) return node.text;
    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase() ?? '';
      if (tag == 'br') return '\n';
      if (tag == 'script' || tag == 'style' || tag == 'noscript' ||
          tag == 'iframe' || tag == 'svg') {
        return '';
      }
      final buf = StringBuffer();
      for (final child in node.nodes) {
        buf.write(_blockAwareText(child));
      }
      var s = buf.toString();
      if (_blockTags.contains(tag)) s = '\n$s\n';
      return s;
    }
    return '';
  }

  /// 压缩空白并保留换行结构：HTML 文本提取的每个换行都对应块级
  /// 元素边界（原文视觉上分段），统一规范为空行做 Markdown 段落
  /// 分隔，否则整篇会被渲染成一段。
  static String _normalizeText(String raw) {
    return raw
        .replaceAll(RegExp(r'[ \t\r]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n+'), '\n\n');
  }

  /// 提取带 [图N] 占位符的正文：相关的图片替换为占位符（顺序与 images 对应），
  /// 无关图片（头像/图标/表情等）直接移除。
  static String _visibleTextWithPlaceholders(
    String baseUrl,
    dom.Element el,
    SiteRule rule,
  ) {
    final clone = el.clone(true);
    for (final tag in ['script', 'style', 'noscript', 'iframe']) {
      for (final s in clone.querySelectorAll(tag)) {
        s.remove();
      }
    }
    final seen = <String>{};
    var idx = 0;
    for (final img in clone.querySelectorAll('img')) {
      // 懒加载优先取 data-src（真实地址），src 可能是占位图
      final src = (img.attributes['data-src'] ?? img.attributes['src'] ?? '')
          .trim();
      if (src.isEmpty || src.startsWith('data:') || src.startsWith('blob:')) {
        img.remove();
        continue;
      }
      if (!_isRelevantImage(img, rule)) {
        img.remove();
        continue;
      }
      final resolved = _resolveUrl(baseUrl, src);
      if (resolved == null ||
          _isBannedUrl(resolved, rule) ||
          !seen.add(resolved)) {
        img.remove();
        continue;
      }
      idx++;
      img.replaceWith(dom.Text('[图$idx]'));
    }
    final raw = _blockAwareText(clone);
    return _normalizeText(raw);
  }

  /// 收集正文容器内的图片地址（支持懒加载 data-src），并解析为绝对地址。
  /// 仅保留与正文相关的图片，按站点规则过滤头像/图标/表情等无关图。
  static List<String> _collectImages(
    String baseUrl,
    dom.Element root,
    SiteRule rule,
  ) {
    final images = <String>[];
    final seen = <String>{};
    for (final img in root.querySelectorAll('img')) {
      // 懒加载优先取 data-src（真实地址），src 可能是占位图
      final src = (img.attributes['data-src'] ?? img.attributes['src'] ?? '')
          .trim();
      if (src.isEmpty || src.startsWith('data:') || src.startsWith('blob:')) {
        continue;
      }
      if (!_isRelevantImage(img, rule)) continue;
      final resolved = _resolveUrl(baseUrl, src);
      if (resolved != null &&
          !_isBannedUrl(resolved, rule) &&
          seen.add(resolved)) {
        images.add(resolved);
      }
    }
    return images;
  }

  /// 过滤头像/图标/表情等无关图片：按类名特征或过小的固定尺寸判断。
  static bool _isRelevantImage(dom.Element img, SiteRule rule) {
    final classes =
        (img.attributes['class'] ?? '').toLowerCase() +
        ' ' +
        (img.attributes['id'] ?? '').toLowerCase();
    for (final b in rule.bannedClassParts) {
      if (classes.contains(b)) return false;
    }
    final w = int.tryParse(img.attributes['width'] ?? '');
    if (w != null && w < 40) return false;
    return true;
  }

  /// 图片 URL 命中站点规则的排除路径（如 /avatar/、/emoji/）则剔除。
  static bool _isBannedUrl(String url, SiteRule rule) {
    if (rule.bannedUrlParts.isEmpty) return false;
    final lower = url.toLowerCase();
    return rule.bannedUrlParts.any((b) => lower.contains(b));
  }

  /// 相对地址基于页面地址解析为绝对地址。
  static String? _resolveUrl(String baseUrl, String src) {
    try {
      final uri = Uri.parse(src);
      if (uri.hasScheme) return src;
      return Uri.parse(baseUrl).resolve(src).toString();
    } catch (_) {
      return null;
    }
  }
}
