import 'package:flutter/material.dart';

class AppConstants {
  static const String defaultCategoryName = '未分类';

  static const String appName = '藏星';

  static const int dbVersion = 7;
  static const String dbName = 'fav_app.db';

  static const int pageSize = 20;

  static const String metaDir = 'meta';
  static const String contentDir = 'content';
  static const String imagesDir = 'images';
}

enum CollectionSortField { collectedAt, publishedAt, title, author, reviewDueAt }

enum CollectionType {
  article,
  comment,
}

enum CollectionStatus {
  unread,
  read,
  learning,
  done,
}

enum SourcePlatform {
  douyin,
  xiaoheihe,
  coolapk,
  other,
}

enum ThemeModeValue {
  system(0, '跟随系统'),
  light(1, '浅色'),
  dark(2, '深色');

  final int value;
  final String label;

  const ThemeModeValue(this.value, this.label);

  static ThemeModeValue fromInt(int? v) => switch (v) {
        1 => light,
        2 => dark,
        _ => system,
      };

  ThemeMode toMaterial() => switch (this) {
        light => ThemeMode.light,
        dark => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

/// ============================================================
/// 唯一的 enum ↔ SQL/Dart String 映射
/// 其他 99% 代码不得硬编码字符串字面量，必须走这些映射
/// ============================================================

class CollectionEnums {
  static const Map<CollectionSortField, String> sortValues = {
    CollectionSortField.collectedAt: 'collected_at',
    CollectionSortField.publishedAt: 'published_at',
    CollectionSortField.title: 'title',
    CollectionSortField.author: 'author',
    CollectionSortField.reviewDueAt: 'review_due_at',
  };

  static const Map<CollectionStatus, String> statusValues = {
    CollectionStatus.unread: 'unread',
    CollectionStatus.read: 'read',
    CollectionStatus.learning: 'learning',
    CollectionStatus.done: 'done',
  };

  static const Map<CollectionType, String> typeValues = {
    CollectionType.article: 'article',
    CollectionType.comment: 'comment',
  };

  static const Map<SourcePlatform, String> platformValues = {
    SourcePlatform.douyin: 'douyin',
    SourcePlatform.xiaoheihe: 'xiaoheihe',
    SourcePlatform.coolapk: 'coolapk',
    SourcePlatform.other: 'other',
  };

  static String sortToSql(CollectionSortField f) =>
      sortValues[f] ?? 'collected_at';

  static String? statusToSql(CollectionStatus? s) =>
      s == null ? null : statusValues[s];

  static String? typeToSql(CollectionType? t) =>
      t == null ? null : typeValues[t];

  static String? platformToSql(SourcePlatform? p) =>
      p == null ? null : platformValues[p];

  static CollectionSortField sortFromSql(String? s) => sortValues.entries
      .firstWhere((e) => e.value == s,
          orElse: () => sortValues.entries.first)
      .key;

  static CollectionStatus? statusFromSql(String? s) {
    if (s == null) return null;
    for (final e in statusValues.entries) {
      if (e.value == s) return e.key;
    }
    return null;
  }

  static CollectionType? typeFromSql(String? s) {
    if (s == null) return null;
    for (final e in typeValues.entries) {
      if (e.value == s) return e.key;
    }
    return null;
  }

  static SourcePlatform? platformFromSql(String? s) {
    if (s == null) return null;
    for (final e in platformValues.entries) {
      if (e.value == s) return e.key;
    }
    return SourcePlatform.other;
  }

  static String statusLabel(CollectionStatus? s) {
    switch (s) {
      case CollectionStatus.unread:
        return '未读';
      case CollectionStatus.read:
        return '已读';
      case CollectionStatus.learning:
        return '学习中';
      case CollectionStatus.done:
        return '完成';
      default:
        return '未知';
    }
  }

  static String platformLabel(SourcePlatform? p) {
    switch (p) {
      case SourcePlatform.douyin:
        return '抖音';
      case SourcePlatform.xiaoheihe:
        return '小黑盒';
      case SourcePlatform.coolapk:
        return '酷安';
      case SourcePlatform.other:
        return '其他';
      default:
        return '未知';
    }
  }

  static String typeLabel(CollectionType? t) {
    switch (t) {
      case CollectionType.article:
        return '长文';
      case CollectionType.comment:
        return '短评';
      default:
        return '未知';
    }
  }

  static Color statusColor(CollectionStatus? s) {
    switch (s) {
      case CollectionStatus.unread:
        return Colors.grey;
      case CollectionStatus.read:
        return Colors.blue;
      case CollectionStatus.learning:
        return Colors.orange;
      case CollectionStatus.done:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  static IconData platformIcon(SourcePlatform? p) {
    switch (p) {
      case SourcePlatform.douyin:
        return Icons.music_video;
      case SourcePlatform.xiaoheihe:
        return Icons.sports_esports;
      case SourcePlatform.coolapk:
        return Icons.android;
      case SourcePlatform.other:
        return Icons.language;
      default:
        return Icons.language;
    }
  }

  static String sortLabel(CollectionSortField s) {
    switch (s) {
      case CollectionSortField.collectedAt:
        return '收藏时间';
      case CollectionSortField.publishedAt:
        return '发布时间';
      case CollectionSortField.title:
        return '标题';
      case CollectionSortField.author:
        return '作者';
      case CollectionSortField.reviewDueAt:
        return '复习时间';
    }
  }
}
