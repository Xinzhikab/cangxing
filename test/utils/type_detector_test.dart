import 'package:flutter_test/flutter_test.dart';
import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/features/save/data/utils/type_detector.dart';

void main() {
  group('TypeDetector.detectType', () {
    final article = CollectionEnums.typeToSql(CollectionType.article)!;
    final comment = CollectionEnums.typeToSql(CollectionType.comment)!;

    test('suggested 优先且做规范化', () {
      expect(TypeDetector.detectType('任意内容', suggested: 'comment'), comment);
      expect(TypeDetector.detectType('任意内容', suggested: 'article'), article);
    });

    test('suggested 为空字符串时回退到内容判断', () {
      expect(TypeDetector.detectType('回复@某人', suggested: ''), comment);
    });

    test('含「回复@」判定为 comment', () {
      expect(TypeDetector.detectType('回复@张三：说得好'), comment);
    });

    test('含「// @」判定为 comment', () {
      expect(TypeDetector.detectType('// @某人 这条评论'), comment);
    });

    test('普通长文判定为 article', () {
      expect(TypeDetector.detectType('这是一篇正文内容，比较长'), article);
    });

    test('空输入判定为 article', () {
      expect(TypeDetector.detectType(''), article);
      expect(TypeDetector.detectType('   '), article);
    });

    test('suggested 优先于内容标记', () {
      // 内容含「回复@」但 suggested=article → article
      expect(TypeDetector.detectType('回复@张三', suggested: 'article'), article);
    });
  });
}
