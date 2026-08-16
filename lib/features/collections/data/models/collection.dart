import 'dart:convert';

class Collection {
  final String id;
  final String title;
  final String type;
  final String sourcePlatform;
  final String sourceUrl;
  final String author;
  final DateTime? publishedAt;
  final DateTime collectedAt;
  final List<String> category;
  final List<String> images;
  final List<String> tags;
  final String note;
  final String status;
  final DateTime? reviewDueAt;
  final String rawInput;
  final String contentMd;

  /// 软删除时间戳（毫秒），null 表示未删除。
  /// 仅由 DB 行的 deleted_at 列填充，meta JSON 中可选。
  final int? deletedAt;

  /// 置顶时间戳（毫秒），null 表示未置顶。
  /// 仅由 DB 行的 pinned_at 列填充，meta JSON 中可选。
  final int? pinnedAt;

  Collection({
    required this.id,
    required this.title,
    required this.type,
    required this.sourcePlatform,
    required this.sourceUrl,
    required this.author,
    this.publishedAt,
    DateTime? collectedAt,
    required this.category,
    required this.images,
    this.tags = const [],
    required this.note,
    required this.status,
    this.reviewDueAt,
    required this.rawInput,
    this.contentMd = '',
    this.deletedAt,
    this.pinnedAt,
  }) : collectedAt = collectedAt ?? DateTime.now();

  factory Collection.fromJson(Map<String, dynamic> json) {
    return Collection(
      id: json['id'] as String,
      title: json['title'] as String,
      type: json['type'] as String,
      sourcePlatform: json['sourcePlatform'] as String,
      sourceUrl: json['sourceUrl'] as String,
      author: json['author'] as String,
      publishedAt: json['publishedAt'] != null
          ? DateTime.parse(json['publishedAt'] as String)
          : null,
      collectedAt: DateTime.parse(json['collectedAt'] as String),
      category: (json['category'] as List<dynamic>).cast<String>(),
      images: (json['images'] as List<dynamic>).cast<String>(),
      tags: ((json['tags'] as List<dynamic>?) ?? const [])
          .whereType<String>()
          .toList(growable: false),
      note: json['note'] as String,
      status: json['status'] as String,
      reviewDueAt: json['reviewDueAt'] != null
          ? DateTime.parse(json['reviewDueAt'] as String)
          : null,
      rawInput: json['rawInput'] as String,
      contentMd: json['contentMd'] as String? ?? '',
      deletedAt: json['deletedAt'] as int?,
      pinnedAt: json['pinnedAt'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'sourcePlatform': sourcePlatform,
      'sourceUrl': sourceUrl,
      'author': author,
      'publishedAt': publishedAt?.toIso8601String(),
      'collectedAt': collectedAt.toIso8601String(),
      'category': category,
      'images': images,
      'tags': tags,
      'note': note,
      'status': status,
      'reviewDueAt': reviewDueAt?.toIso8601String(),
      'rawInput': rawInput,
      'contentMd': contentMd,
      if (deletedAt != null) 'deletedAt': deletedAt,
      if (pinnedAt != null) 'pinnedAt': pinnedAt,
    };
  }

  Collection copyWith({
    String? id,
    String? title,
    String? type,
    String? sourcePlatform,
    String? sourceUrl,
    String? author,
    DateTime? publishedAt,
    DateTime? collectedAt,
    List<String>? category,
    List<String>? images,
    List<String>? tags,
    String? note,
    String? status,
    DateTime? reviewDueAt,
    String? rawInput,
    String? contentMd,
    int? deletedAt,
    bool clearDeletedAt = false,
    int? pinnedAt,
    bool clearPinnedAt = false,
  }) {
    return Collection(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      sourcePlatform: sourcePlatform ?? this.sourcePlatform,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      author: author ?? this.author,
      publishedAt: publishedAt ?? this.publishedAt,
      collectedAt: collectedAt ?? this.collectedAt,
      category: category ?? this.category,
      images: images ?? this.images,
      tags: tags ?? this.tags,
      note: note ?? this.note,
      status: status ?? this.status,
      reviewDueAt: reviewDueAt ?? this.reviewDueAt,
      rawInput: rawInput ?? this.rawInput,
      contentMd: contentMd ?? this.contentMd,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      pinnedAt: clearPinnedAt ? null : (pinnedAt ?? this.pinnedAt),
    );
  }
}
