import 'package:flutter_test/flutter_test.dart';
import 'package:fav_app/features/save/data/utils/normalize_utils.dart';

void main() {
  group('normalizeTags', () {
    test('空输入返回空列表', () {
      expect(normalizeTags([], []), <String>[]);
    });

    test('无已有标签时保留 AI 原词（去首尾空白）', () {
      expect(normalizeTags(['  游戏  ', '攻略'], []), ['游戏', '攻略']);
    });

    test('忽略大小写完全一致时替换为已有标签原名', () {
      expect(normalizeTags(['Flutter'], ['flutter']), ['flutter']);
      expect(normalizeTags(['FLUTTER'], ['Flutter']), ['Flutter']);
    });

    test('互相包含且长度达标时替换为已有标签', () {
      // AI「地平线4」⊂ 已有「极限竞速地平线4」：较短方长度 4 >=2，
      // 4*2=8 >= 较长方长度 8，命中
      expect(
        normalizeTags(['地平线4'], ['极限竞速地平线4']),
        ['极限竞速地平线4'],
      );
    });

    test('泛词过短不被长标签吞并', () {
      // 「游戏」(2) vs「极限竞速地平线4」(8)：2*2=4 < 8，不命中 → 保留 AI 原词
      expect(normalizeTags(['游戏'], ['极限竞速地平线4']), ['游戏']);
    });

    test('单字标签不触发包含匹配', () {
      expect(normalizeTags(['a'], ['ab']), ['a']);
    });

    test('去重：AI 重复 + 与已有重复都只保留一份', () {
      // 输入顺序：游戏(新)、游戏(重复)、攻略(命中已有) → 输出 [游戏, 攻略]
      expect(normalizeTags(['游戏', '游戏', '攻略'], ['攻略']), ['游戏', '攻略']);
    });

    test('空白/空字符串标签被跳过', () {
      expect(normalizeTags(['', '  ', '游戏'], []), ['游戏']);
    });

    test('保持输入顺序（命中者按出现顺序写入）', () {
      expect(normalizeTags(['攻略', '游戏'], ['游戏', '攻略']), ['攻略', '游戏']);
    });

    test('超长字符串正常处理', () {
      final long = '标签' * 500;
      expect(normalizeTags([long], []), [long]);
    });

    test('特殊字符标签保留', () {
      expect(
        normalizeTags(['C++', 'Node.js', 'emoji😀'], []),
        ['C++', 'Node.js', 'emoji😀'],
      );
    });
  });
}
