/// 站点专属提取规则：按域名匹配，覆盖正文容器选择器与图片过滤规则。
/// 可在此为不同站点定制，未命中的站点走默认通用规则。
class SiteRule {
  /// 匹配的域名（host 子串匹配；空串表示默认规则）
  final String domain;

  /// 正文容器 CSS 选择器，按优先级排列
  final List<String> contentSelectors;

  /// 图片过滤：class/id 包含这些词即排除
  final List<String> bannedClassParts;

  /// 图片过滤：URL 包含这些路径即排除
  final List<String> bannedUrlParts;

  const SiteRule({
    required this.domain,
    required this.contentSelectors,
    this.bannedClassParts = const [],
    this.bannedUrlParts = const [],
  });
}

/// 站点规则注册表：想给新站点定制规则，在这里加一条即可。
class SiteRuleRegistry {
  static const SiteRule defaultRule = SiteRule(
    domain: '',
    contentSelectors: [
      'article',
      'main',
      '.post',
      '.post-content',
      '.article-content',
      '.article',
      '.content',
      '.rich-content',
      '#content',
      '[class*="article"]',
      '[class*="content"]',
    ],
    bannedClassParts: [
      'avatar', 'icon', 'logo', 'emoji', 'face', 'thumb',
      'badge', 'smiley', 'sticker', 'default',
    ],
  );

  static const List<SiteRule> _rules = [
    // 小黑盒：正文容器类名、作者/评论/点赞等无关图片按类名与 URL 路径过滤。
    // 详情页有两种结构，都覆盖：
    //   1) .post__content / .hb-article（NevilNell KDE 帖这类，正文内嵌图 .img-item）
    //   2) .image-text__content 纯正文 + 首图轮播 .header-image__item img（地平线帖这类）
    // 标题 .section-title__content、作者 .link-user__username、时间 .link-data__time 通用。
    // 正文容器优先取纯正文，其次完整帖子容器，最后才走 [class*="content"] 兜底
    // （避免命中导航条 nav-content）。
    SiteRule(
      domain: 'xiaoheihe.cn',
      contentSelectors: [
        '.post__content',
        '.image-text__content',
        '[class*="hb-bbs-link"]',
        'article',
        '.post-content',
        '.article-content',
        '.rich-content',
        '[class*="post-content"]',
        '[class*="article-content"]',
        '[class*="rich-content"]',
        '[class*="content"]',
      ],
      bannedClassParts: [
        'avatar', 'icon', 'logo', 'emoji', 'face', 'thumb', 'badge',
        'sticker', 'author', 'comment', 'praise', 'like', 'share', 'qr',
        'user', 'follow', 'reply', 'tip', 'vote', 'medal', 'info-box',
        'download', 'cpt',
      ],
      bannedUrlParts: [
        '/avatar/',
        '/icons/',
        '/emoji/',
        '/sticker/',
        '/favicon',
      ],
    ),
  ];

  /// 按 URL 匹配专属规则，未命中返回默认通用规则。
  static SiteRule ruleFor(String url) {
    try {
      final host = Uri.parse(url).host.toLowerCase();
      for (final rule in _rules) {
        if (host.contains(rule.domain)) return rule;
      }
    } catch (_) {}
    return defaultRule;
  }
}
