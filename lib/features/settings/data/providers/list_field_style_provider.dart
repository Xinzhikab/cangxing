import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 收藏列表条目（首页文章卡片）显示配置：栏目开关 + 排版参数自由组合，
/// 另有预设方案一键应用。
class ListFieldStyle {
  /// 左侧圆形图标（平台名首字）
  final bool showIcon;

  /// 副标题中的平台名
  final bool showPlatform;

  /// 副标题中的作者
  final bool showAuthor;

  /// 副标题中的收藏时间
  final bool showTime;

  /// 副标题中的分类路径
  final bool showCategory;

  /// 卡片底部的标签 chips
  final bool showTags;

  /// 正文摘要（首行非空文本，最多 2 行）
  final bool showSnippet;

  /// 「想学 / 已完成」状态徽标
  final bool showStatusBadge;

  /// 标题最大行数（1-3）
  final int titleLines;

  /// 紧凑模式：减小内边距，列表更密
  final bool compact;

  const ListFieldStyle({
    this.showIcon = true,
    this.showPlatform = true,
    this.showAuthor = true,
    this.showTime = true,
    this.showCategory = false,
    this.showTags = false,
    this.showSnippet = false,
    this.showStatusBadge = true,
    this.titleLines = 1,
    this.compact = false,
  });

  ListFieldStyle copyWith({
    bool? showIcon,
    bool? showPlatform,
    bool? showAuthor,
    bool? showTime,
    bool? showCategory,
    bool? showTags,
    bool? showSnippet,
    bool? showStatusBadge,
    int? titleLines,
    bool? compact,
  }) {
    return ListFieldStyle(
      showIcon: showIcon ?? this.showIcon,
      showPlatform: showPlatform ?? this.showPlatform,
      showAuthor: showAuthor ?? this.showAuthor,
      showTime: showTime ?? this.showTime,
      showCategory: showCategory ?? this.showCategory,
      showTags: showTags ?? this.showTags,
      showSnippet: showSnippet ?? this.showSnippet,
      showStatusBadge: showStatusBadge ?? this.showStatusBadge,
      titleLines: titleLines ?? this.titleLines,
      compact: compact ?? this.compact,
    );
  }
}

/// 预设方案（可一键应用，应用后仍可微调）
const Map<String, ListFieldStyle> kListFieldPresets = {
  '标准': ListFieldStyle(),
  '简洁': ListFieldStyle(
    showIcon: true,
    showPlatform: false,
    showAuthor: false,
    showTime: false,
    compact: true,
  ),
  '纯文字': ListFieldStyle(
    showIcon: false,
    showPlatform: true,
    showAuthor: false,
    showTime: false,
  ),
  '详细': ListFieldStyle(
    showIcon: true,
    showPlatform: true,
    showAuthor: true,
    showTime: true,
    showCategory: true,
    showTags: true,
    showSnippet: true,
    titleLines: 2,
  ),
};

class ListFieldStyleNotifier extends Notifier<ListFieldStyle> {
  static const String _kPrefix = 'list_field_';

  @override
  ListFieldStyle build() {
    _load();
    return const ListFieldStyle();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = ListFieldStyle(
      showIcon: prefs.getBool('${_kPrefix}icon') ?? true,
      showPlatform: prefs.getBool('${_kPrefix}platform') ?? true,
      showAuthor: prefs.getBool('${_kPrefix}author') ?? true,
      showTime: prefs.getBool('${_kPrefix}time') ?? true,
      showCategory: prefs.getBool('${_kPrefix}category') ?? false,
      showTags: prefs.getBool('${_kPrefix}tags') ?? false,
      showSnippet: prefs.getBool('${_kPrefix}snippet') ?? false,
      showStatusBadge: prefs.getBool('${_kPrefix}status_badge') ?? true,
      titleLines: prefs.getInt('${_kPrefix}title_lines') ?? 1,
      compact: prefs.getBool('${_kPrefix}compact') ?? false,
    );
  }

  Future<void> update({
    bool? showIcon,
    bool? showPlatform,
    bool? showAuthor,
    bool? showTime,
    bool? showCategory,
    bool? showTags,
    bool? showSnippet,
    bool? showStatusBadge,
    int? titleLines,
    bool? compact,
  }) async {
    state = state.copyWith(
      showIcon: showIcon,
      showPlatform: showPlatform,
      showAuthor: showAuthor,
      showTime: showTime,
      showCategory: showCategory,
      showTags: showTags,
      showSnippet: showSnippet,
      showStatusBadge: showStatusBadge,
      titleLines: titleLines,
      compact: compact,
    );
    await _persist();
  }

  Future<void> applyPreset(ListFieldStyle preset) async {
    state = preset;
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_kPrefix}icon', state.showIcon);
    await prefs.setBool('${_kPrefix}platform', state.showPlatform);
    await prefs.setBool('${_kPrefix}author', state.showAuthor);
    await prefs.setBool('${_kPrefix}time', state.showTime);
    await prefs.setBool('${_kPrefix}category', state.showCategory);
    await prefs.setBool('${_kPrefix}tags', state.showTags);
    await prefs.setBool('${_kPrefix}snippet', state.showSnippet);
    await prefs.setBool('${_kPrefix}status_badge', state.showStatusBadge);
    await prefs.setInt('${_kPrefix}title_lines', state.titleLines);
    await prefs.setBool('${_kPrefix}compact', state.compact);
  }
}

final listFieldStyleProvider =
    NotifierProvider<ListFieldStyleNotifier, ListFieldStyle>(
  ListFieldStyleNotifier.new,
);
