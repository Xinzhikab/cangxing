import 'package:fav_app/core/constants/app_constants.dart';

class TypeDetector {
  static String detectType(String rawInput, {String? suggested}) {
    if (suggested != null && suggested.isNotEmpty) {
      return CollectionEnums.typeToSql(CollectionEnums.typeFromSql(suggested))!;
    }

    final trimmed = rawInput.trim();

    if (trimmed.contains('回复@') || trimmed.contains('// @')) {
      return CollectionEnums.typeToSql(CollectionType.comment)!;
    }

    return CollectionEnums.typeToSql(CollectionType.article)!;
  }
}
