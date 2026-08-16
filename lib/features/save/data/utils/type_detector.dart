class TypeDetector {
  static String detectType(String rawInput, {String? suggested}) {
    if (suggested != null && suggested.isNotEmpty) {
      return suggested;
    }

    final trimmed = rawInput.trim();

    if (trimmed.contains('回复@') || trimmed.contains('// @')) {
      return 'comment';
    }

    return 'article';
  }
}
