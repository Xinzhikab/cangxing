import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阅读页排版样式（效仿「阅读」App 的阅读界面设置）。
class ReadingStyle {
  /// 正文字号
  final double fontSize;

  /// 正文行高倍率
  final double lineHeight;

  /// 正文左右页边距
  final double pagePadding;

  const ReadingStyle({
    this.fontSize = 15,
    this.lineHeight = 1.6,
    this.pagePadding = 16,
  });

  ReadingStyle copyWith({
    double? fontSize,
    double? lineHeight,
    double? pagePadding,
  }) {
    return ReadingStyle(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      pagePadding: pagePadding ?? this.pagePadding,
    );
  }
}

class ReadingStyleNotifier extends Notifier<ReadingStyle> {
  static const String _kFontSize = 'reading_font_size';
  static const String _kLineHeight = 'reading_line_height';
  static const String _kPagePadding = 'reading_page_padding';

  @override
  ReadingStyle build() {
    // 同步读缓存值：SharedPreferences 在 AppSettings 首次加载时已初始化过，
    // 这里用异步补读的方式保持简单——先给默认值，异步读到再更新
    _load();
    return const ReadingStyle();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = ReadingStyle(
      fontSize: prefs.getDouble(_kFontSize) ?? 15,
      lineHeight: prefs.getDouble(_kLineHeight) ?? 1.6,
      pagePadding: prefs.getDouble(_kPagePadding) ?? 16,
    );
  }

  Future<void> update({
    double? fontSize,
    double? lineHeight,
    double? pagePadding,
  }) async {
    state = state.copyWith(
      fontSize: fontSize,
      lineHeight: lineHeight,
      pagePadding: pagePadding,
    );
    final prefs = await SharedPreferences.getInstance();
    if (fontSize != null) await prefs.setDouble(_kFontSize, fontSize);
    if (lineHeight != null) await prefs.setDouble(_kLineHeight, lineHeight);
    if (pagePadding != null) {
      await prefs.setDouble(_kPagePadding, pagePadding);
    }
  }

  Future<void> reset() => update(fontSize: 15, lineHeight: 1.6, pagePadding: 16);
}

final readingStyleProvider =
    NotifierProvider<ReadingStyleNotifier, ReadingStyle>(
  ReadingStyleNotifier.new,
);
