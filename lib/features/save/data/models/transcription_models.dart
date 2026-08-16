enum TranscriptionStep { fetching, transcribing, downloadingImages, done, failed }

class TranscriptionProgress {
  final TranscriptionStep step;
  final String? message;
  final int? current;
  final int? total;

  const TranscriptionProgress({
    required this.step,
    this.message,
    this.current,
    this.total,
  });
}

class TranscriptionResult {
  final String title;
  final String contentMd;
  final String author;
  final String platform;
  final DateTime? publishedAt;
  final List<String> imageUrls;
  final List<String> tags;

  /// AI 建议的顶层文件夹名（只能是本地已有文件夹，不新建）
  final String category;

  /// AI 思考链（reasoning_content），用于转录日志排查
  final String aiReasoning;

  /// AI 原始输出（未解析的 content），用于转录日志排查
  final String aiRawOutput;

  /// AI 调用失败原因（失败不影响正文保存，仅记录）
  final String aiError;

  const TranscriptionResult({
    required this.title,
    required this.contentMd,
    required this.author,
    required this.platform,
    this.publishedAt,
    required this.imageUrls,
    this.tags = const [],
    this.category = '',
    this.aiReasoning = '',
    this.aiRawOutput = '',
    this.aiError = '',
  });

  factory TranscriptionResult.fromJson(Map<String, dynamic> json) {
    return TranscriptionResult(
      title: json['title'] as String? ?? '',
      contentMd: json['content_md'] as String? ?? '',
      author: json['author'] as String? ?? '',
      platform: json['platform'] as String? ?? 'other',
      publishedAt: parsePublishedAt(json['published_at'] as String?),
      imageUrls: [],
      tags: ((json['tags'] as List<dynamic>?) ?? const [])
          .whereType<String>()
          .toList(growable: false),
      category: (json['category'] as String? ?? '').trim(),
    );
  }

  /// 解析 AI 返回的发布时间。
  /// 空串/格式错误/明显不合理（如 LLM 用 1970-01-01 充当占位）时返回 null，
  /// 由调用方回退到页面抓取的发布日期。
  static DateTime? parsePublishedAt(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    final d = DateTime.tryParse(s);
    if (d == null) return null;
    if (d.year < 2000 || d.year > 2100) return null;
    return d;
  }

  TranscriptionResult copyWith({
    String? title,
    String? contentMd,
    String? author,
    String? platform,
    DateTime? publishedAt,
    List<String>? imageUrls,
    List<String>? tags,
    String? category,
    String? aiReasoning,
    String? aiRawOutput,
    String? aiError,
  }) {
    return TranscriptionResult(
      title: title ?? this.title,
      contentMd: contentMd ?? this.contentMd,
      author: author ?? this.author,
      platform: platform ?? this.platform,
      publishedAt: publishedAt ?? this.publishedAt,
      imageUrls: imageUrls ?? this.imageUrls,
      tags: tags ?? this.tags,
      category: category ?? this.category,
      aiReasoning: aiReasoning ?? this.aiReasoning,
      aiRawOutput: aiRawOutput ?? this.aiRawOutput,
      aiError: aiError ?? this.aiError,
    );
  }
}

enum TranscriptionFailureReason { network, llmError, parseError, timeout, unknown }

class TranscriptionException implements Exception {
  final TranscriptionFailureReason reason;
  final String? message;

  const TranscriptionException(this.reason, [this.message]);

  @override
  String toString() {
    if (message != null) {
      return 'TranscriptionException: $reason - $message';
    }
    return 'TranscriptionException: $reason';
  }
}
