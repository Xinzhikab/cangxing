import 'package:flutter_test/flutter_test.dart';

import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/collections/data/models/category.dart';
import 'package:fav_app/features/save/data/models/transcription_models.dart';
import 'package:fav_app/features/save/data/services/llm_client.dart';
import 'package:fav_app/features/settings/data/providers/app_settings_provider.dart';

void main() {
  group('AppConstants', () {
    test('数据库名称正确', () {
      expect(AppConstants.dbName, 'fav_app.db');
    });

    test('目录常量正确', () {
      expect(AppConstants.metaDir, 'meta');
      expect(AppConstants.contentDir, 'content');
      expect(AppConstants.imagesDir, 'images');
    });

    test('状态常量', () {
      expect(CollectionStatus.unread, 'unread');
      expect(CollectionStatus.read, 'read');
      expect(CollectionStatus.learning, 'learning');
      expect(CollectionStatus.done, 'done');
    });

    test('平台常量', () {
      expect(SourcePlatform.douyin, 'douyin');
      expect(SourcePlatform.coolapk, 'coolapk');
      expect(SourcePlatform.xiaoheihe, 'xiaoheihe');
      expect(SourcePlatform.other, 'other');
    });

    test('类型常量', () {
      expect(CollectionType.article, 'article');
      expect(CollectionType.comment, 'comment');
    });
  });

  group('Collection Model', () {
    final now = DateTime(2026, 8, 13, 14, 30);

    final collection = Collection(
      id: 'test-id-001',
      title: 'Flutter 异步编程指南',
      type: CollectionType.article,
      sourcePlatform: SourcePlatform.coolapk,
      sourceUrl: 'https://www.coolapk.com/article/12345',
      author: '数码爱好者',
      publishedAt: DateTime(2026, 8, 10),
      collectedAt: now,
      category: ['技术', 'Flutter'],
      images: ['images/test-id-001/img_001.jpg'],
      note: '这篇讲得很好',
      status: CollectionStatus.unread,
      rawInput: '原始文本内容',
      contentMd: '# 标题\n正文内容',
    );

    test('toJson 序列化完整', () {
      final json = collection.toJson();
      expect(json['id'], 'test-id-001');
      expect(json['title'], 'Flutter 异步编程指南');
      expect(json['type'], CollectionType.article);
      expect(json['sourcePlatform'], SourcePlatform.coolapk);
      expect(json['author'], '数码爱好者');
      expect(json['status'], CollectionStatus.unread);
      expect(json['contentMd'], '# 标题\n正文内容');
      expect(json['category'], ['技术', 'Flutter']);
      expect(json['images'].length, 1);
    });

    test('fromJson 反序列化 round-trip', () {
      final json = collection.toJson();
      final restored = Collection.fromJson(json);
      expect(restored.id, collection.id);
      expect(restored.title, collection.title);
      expect(restored.type, collection.type);
      expect(restored.sourcePlatform, collection.sourcePlatform);
      expect(restored.author, collection.author);
      expect(restored.status, collection.status);
      expect(restored.contentMd, collection.contentMd);
      expect(restored.category, collection.category);
      expect(restored.images, collection.images);
      expect(restored.note, collection.note);
      expect(restored.rawInput, collection.rawInput);
    });

    test('copyWith 部分更新', () {
      final updated = collection.copyWith(
        status: CollectionStatus.learning,
        reviewDueAt: DateTime(2026, 8, 14),
        note: '更新后的笔记',
      );
      expect(updated.status, CollectionStatus.learning);
      expect(updated.reviewDueAt, DateTime(2026, 8, 14));
      expect(updated.note, '更新后的笔记');
      // 未改动的字段保持原值
      expect(updated.id, collection.id);
      expect(updated.title, collection.title);
    });

    test('reviewDueAt 默认 null', () {
      expect(collection.reviewDueAt, isNull);
    });

    test('contentMd 默认空字符串', () {
      final minimal = Collection(
        id: 'min',
        title: '最小',
        type: CollectionType.article,
        sourcePlatform: SourcePlatform.other,
        sourceUrl: '',
        author: '',
        category: [],
        images: [],
        note: '',
        status: CollectionStatus.unread,
        rawInput: '',
      );
      expect(minimal.contentMd, '');
    });
  });

  group('Category Model', () {
    test('创建与 copyWith', () {
      final cat = Category(
        id: 'cat-001',
        name: '技术',
        parentId: null,
        sortOrder: 0,
        createdAt: DateTime(2026, 8, 13),
      );
      expect(cat.name, '技术');
      expect(cat.parentId, isNull);

      final child = cat.copyWith(name: 'Flutter', parentId: 'cat-001', sortOrder: 1);
      expect(child.name, 'Flutter');
      expect(child.parentId, 'cat-001');
      expect(child.sortOrder, 1);
      expect(child.id, cat.id);
    });
  });

  group('TranscriptionResult', () {
    test('fromJson 解析 LLM 返回的完整 JSON', () {
      final json = {
        'title': 'Flutter 性能优化指南',
        'content_md': '# 性能优化\n\n## 1. Widget 复用\n使用 const 构造器。',
        'author': 'Flutter 开发者',
        'platform': 'coolapk',
        'published_at': '2026-08-10T12:00:00',
      };
      final result = TranscriptionResult.fromJson(json);
      expect(result.title, 'Flutter 性能优化指南');
      expect(result.contentMd, contains('# 性能优化'));
      expect(result.author, 'Flutter 开发者');
      expect(result.platform, 'coolapk');
      expect(result.publishedAt, DateTime(2026, 8, 10, 12, 0, 0));
    });

    test('fromJson 缺失字段使用默认值', () {
      final result = TranscriptionResult.fromJson({});
      expect(result.title, '');
      expect(result.contentMd, '');
      expect(result.author, '');
      expect(result.platform, 'other');
      expect(result.publishedAt, isNull);
    });

    test('published_at 空字符串解析为 null', () {
      final result = TranscriptionResult.fromJson({
        'published_at': '',
      });
      expect(result.publishedAt, isNull);
    });

    test('copyWith 部分更新', () {
      final original = TranscriptionResult(
        title: '原始标题',
        contentMd: '# 正文',
        author: '作者',
        platform: 'other',
        imageUrls: ['http://example.com/a.jpg'],
      );
      final updated = original.copyWith(
        title: '新标题',
        imageUrls: ['local/path/a.jpg'],
      );
      expect(updated.title, '新标题');
      expect(updated.contentMd, '# 正文');
      expect(updated.imageUrls, ['local/path/a.jpg']);
    });
  });

  group('TranscriptionException', () {
    test('toString 包含原因和消息', () {
      final e = TranscriptionException(
        TranscriptionFailureReason.network,
        '连接超时',
      );
      expect(e.reason, TranscriptionFailureReason.network);
      expect(e.toString(), contains('network'));
      expect(e.toString(), contains('连接超时'));
    });

    test('不带消息的异常', () {
      final e = TranscriptionException(TranscriptionFailureReason.timeout);
      expect(e.message, isNull);
      expect(e.toString(), contains('timeout'));
    });
  });

  group('Transcription Prompt Presets', () {
    test('预设包含 5 种风格', () {
      expect(transcriptionPromptPresets.length, 5);
      expect(transcriptionPromptPresets.containsKey('默认'), isTrue);
      expect(transcriptionPromptPresets.containsKey('详细排版'), isTrue);
      expect(transcriptionPromptPresets.containsKey('简洁提取'), isTrue);
      expect(transcriptionPromptPresets.containsKey('小黑盒攻略'), isTrue);
      expect(transcriptionPromptPresets.containsKey('酷安文章'), isTrue);
    });

    test('提示词模板替换 \$collectionType', () {
      final template = transcriptionPromptPresets['默认']!;
      final result = template.replaceAll(r'$collectionType', '文章');
      expect(result, contains('文章'));
      expect(result, isNot(contains(r'$collectionType')));
    });

    test('小黑盒预设 platform 固定为 xiaoheihe', () {
      final preset = transcriptionPromptPresets['小黑盒攻略']!;
      expect(preset, contains('"platform":"xiaoheihe"'));
    });

    test('酷安预设 platform 固定为 coolapk', () {
      final preset = transcriptionPromptPresets['酷安文章']!;
      expect(preset, contains('"platform":"coolapk"'));
    });
  });

  group('LlmConfig', () {
    test('构造正确', () {
      final config = LlmConfig(
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-test',
        model: 'deepseek-chat',
      );
      expect(config.baseUrl, 'https://api.deepseek.com/v1');
      expect(config.apiKey, 'sk-test');
      expect(config.model, 'deepseek-chat');
    });
  });
}
