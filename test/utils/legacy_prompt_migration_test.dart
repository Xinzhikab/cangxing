import 'package:flutter_test/flutter_test.dart';
import 'package:fav_app/features/settings/data/providers/app_settings_provider.dart';

void main() {
  group('migrateLegacyPrompt', () {
    test('已知旧预设原文 → 迁移到对应新预设（含 "tags"）', () {
      for (final entry in legacyPromptMigration.entries) {
        final migrated = migrateLegacyPrompt(entry.key);
        expect(migrated, entry.value,
            reason: '旧预设应迁移到 legacyPromptMigration 中指定的目标');
        expect(migrated, contains('"tags"'),
            reason: '迁移后的新预设应要求 AI 输出 tags 字段');
      }
    });

    test('通用旧版（含 content_md 且无 "tags"）→ 默认预设', () {
      const oldGeneric =
          '把内容转成 Markdown，输出 {"title":"","content_md":"","author":""}';
      final migrated = migrateLegacyPrompt(oldGeneric);
      expect(migrated, transcriptionPromptPresets['默认']);
      expect(migrated, contains('"tags"'));
    });

    test('已是新版默认预设 → 原样返回', () {
      final current = transcriptionPromptPresets['默认']!;
      expect(migrateLegacyPrompt(current), current);
    });

    test('用户自定义提示词（无 content_md）→ 原样返回', () {
      const custom = '你是我的专属标签助手，只输出 JSON。';
      expect(migrateLegacyPrompt(custom), custom);
    });

    test('含 content_md 且含 "tags" → 不迁移（已是新版）', () {
      const neo = '输出 {"content_md":"","tags":[]}';
      expect(migrateLegacyPrompt(neo), neo);
    });

    test('空字符串 → 原样返回空串', () {
      expect(migrateLegacyPrompt(''), '');
    });

    test('legacyPromptMigration 的每个 value 都来自预设 map', () {
      for (final v in legacyPromptMigration.values) {
        expect(transcriptionPromptPresets.values, contains(v));
      }
    });
  });
}
