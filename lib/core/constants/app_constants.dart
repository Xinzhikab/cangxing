class AppConstants {
  static const String defaultCategoryName = '未分类';

  static const String appName = '藏星';

  static const int dbVersion = 5;
  static const String dbName = 'fav_app.db';

  static const int pageSize = 20;

  static const String metaDir = 'meta';
  static const String contentDir = 'content';
  static const String imagesDir = 'images';
}

class CollectionType {
  static const String article = 'article';
  static const String comment = 'comment';
}

class CollectionStatus {
  static const String unread = 'unread';
  static const String read = 'read';
  static const String learning = 'learning';
  static const String done = 'done';
}

class SourcePlatform {
  static const String douyin = 'douyin';
  static const String xiaoheihe = 'xiaoheihe';
  static const String coolapk = 'coolapk';
  static const String other = 'other';
}

enum ItemType {
  article,
  comment,
}

enum ItemStatus {
  unread,
  read,
  learning,
  done,
}

enum ItemPlatform {
  douyin,
  xiaoheihe,
  coolapk,
  other,
}
