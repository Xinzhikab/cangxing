import 'package:flutter_test/flutter_test.dart';
import 'package:fav_app/features/save/data/utils/normalize_utils.dart';

void main() {
  group('normalizeCategory', () {
    test('空输入返回空串', () {
      expect(normalizeCategory('', ['游戏']), '');
      expect(normalizeCategory('   ', ['游戏']), '');
    });

    test('已有分类为空时返回空串（不生成新文件夹）', () {
      expect(normalizeCategory('游戏', []), '');
    });

    test('忽略大小写完全一致命中', () {
      expect(normalizeCategory('Flutter', ['flutter']), 'flutter');
      expect(normalizeCategory('FLUTTER', ['Flutter']), 'Flutter');
    });

    test('互相包含且较短方长度 >=2 命中', () {
      // AI「游戏攻略」包含已有「游戏」(2>=2) → 命中已有
      expect(normalizeCategory('游戏攻略', ['游戏']), '游戏');
    });

    test('未命中返回空串', () {
      expect(normalizeCategory('新分类', ['游戏', '技术']), '');
    });

    test('单字 AI 不触发包含匹配', () {
      expect(normalizeCategory('游', ['游戏']), '');
    });

    test('去掉首尾空白后匹配', () {
      expect(normalizeCategory('  游戏  ', ['游戏']), '游戏');
    });

    test('特殊字符分类', () {
      expect(normalizeCategory('C++', ['C++']), 'C++');
      expect(normalizeCategory('C++', ['Python']), '');
    });
  });
}
