/// 标签 / 文件夹归一化纯函数。
///
/// 从 `SaveController` 中提取出来作为顶层公开函数，便于单元测试。
/// 逻辑与原 `SaveController._normalizeTags` / `_normalizeCategory` 完全一致。
library;

/// 标签模糊归一化：AI 生成的标签与已有标签模糊匹配时，自动替换为已有标签，
/// 避免「地平线4」/「极限竞速地平线4」这类变体标签越攒越多。
///
/// 匹配规则（按优先级）：
/// 1. 忽略大小写与首尾空白后完全一致 → 替换；
/// 2. 互相包含（如 AI「地平线4」⊂ 已有「极限竞速地平线4」）且较短方
///    长度 ≥2、较短方不短于较长方的 50% → 替换（比例限制防止「游戏」
///    这类泛词误吞并长标签）；
/// 3. 无匹配 → 保留 AI 原词（作为新标签候选，用户在确认框可剔除）。
List<String> normalizeTags(
  List<String> aiTags,
  List<String> existingTags,
) {
  // 小写键 → 已有标签原名
  final byKey = <String, String>{};
  for (final e in existingTags) {
    final k = e.trim().toLowerCase();
    if (k.isNotEmpty) byKey.putIfAbsent(k, () => e);
  }
  final out = <String>[];
  for (final raw in aiTags) {
    final t = raw.trim();
    if (t.isEmpty) continue;
    final k = t.toLowerCase();
    // 1) 忽略大小写完全一致
    final exact = byKey[k];
    if (exact != null) {
      if (!out.contains(exact)) out.add(exact);
      continue;
    }
    // 2) 互相包含（带长度护栏）
    String? contained;
    for (final entry in byKey.entries) {
      final ek = entry.key;
      final shorter = ek.length < k.length ? ek : k;
      final longer = ek.length < k.length ? k : ek;
      if (shorter.length >= 2 &&
          shorter.length * 2 >= longer.length &&
          longer.contains(shorter)) {
        contained = entry.value;
        break;
      }
    }
    if (contained != null) {
      if (!out.contains(contained)) out.add(contained);
      continue;
    }
    // 3) 未匹配 → 保留 AI 原词，作为新标签候选
    if (!out.contains(t)) out.add(t);
  }
  return out;
}

/// 文件夹归一化：与标签不同，AI 建议的文件夹必须命中本地已有文件夹，
/// 未命中直接丢弃（返回空串，回退保存页选择的目录），不生成新文件夹。
///
/// 匹配规则：
/// 1. 忽略大小写与首尾空白后完全一致 → 命中；
/// 2. 互相包含且较短方长度 ≥2（防单字误匹配）→ 命中；
/// 3. 无匹配 → 空串。
String normalizeCategory(
  String aiCategory,
  List<String> existingCategories,
) {
  final t = aiCategory.trim();
  if (t.isEmpty || existingCategories.isEmpty) return '';
  final k = t.toLowerCase();
  for (final e in existingCategories) {
    if (e.toLowerCase() == k) return e;
  }
  for (final e in existingCategories) {
    final ek = e.toLowerCase();
    final shorter = ek.length < k.length ? ek : k;
    if (shorter.length >= 2 &&
        (ek.contains(k) || k.contains(ek)) &&
        shorter.length * 2 >= (ek.length < k.length ? k : ek).length) {
      return e;
    }
  }
  return '';
}
