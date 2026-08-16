import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/features/settings/data/models/app_settings.dart';

Set<String> _decodeSet(String? s) =>
    s == null
        ? {'local'}
        : (jsonDecode(s) as List<dynamic>).map((e) => e as String).toSet();

const String _defaultPrompt = '你是标签提取助手。阅读用户提供的\$collectionType内容，仅提取主题标签；正文、标题、作者、时间等均由页面提取，不要 AI 生成。只输出合法 JSON：{"tags":["关键词1","关键词2"]}。tags 提取 3-6 个简短主题关键词。不要输出 JSON 以外的任何字符。';

const Map<String, String> transcriptionPromptPresets = {
  '默认': '你是标签提取助手。阅读用户提供的\$collectionType内容，仅提取主题标签；正文、标题、作者、时间等均由页面提取，不要 AI 生成。只输出合法 JSON：{"tags":["关键词1","关键词2"]}。tags 提取 3-6 个简短主题关键词。不要输出 JSON 以外的任何字符。',
  '精简（1-3 个）': '你是标签提取助手。阅读用户提供的内容，仅提取最核心的主题标签。只输出合法 JSON：{"tags":["关键词1","关键词2"]}。tags 只要 1-3 个最核心的关键词。不要输出 JSON 以外的任何字符。',
  '详细（5-10 个）': '你是标签提取助手。阅读用户提供的内容，仅提取主题标签，覆盖主题、领域、关键实体等多角度。只输出合法 JSON：{"tags":["关键词1","关键词2"]}。tags 提取 5-10 个关键词。不要输出 JSON 以外的任何字符。',
  '游戏向': '你是游戏内容标签助手。阅读用户提供的游戏相关内容（攻略/资讯/评测），提取主题标签，可包含游戏名、角色/装备名、玩法类型等。只输出合法 JSON：{"tags":["关键词1","关键词2"]}。tags 提取 3-8 个。不要输出 JSON 以外的任何字符。',
  '数码向': '你是数码内容标签助手。阅读用户提供的数码相关内容（评测/资讯/技巧），提取主题标签，可包含品牌、机型、技术名词等。只输出合法 JSON：{"tags":["关键词1","关键词2"]}。tags 提取 3-8 个。不要输出 JSON 以外的任何字符。',
};

/// 旧版「转录 Markdown」提示词 → 新版「仅提取标签」提示词。
/// 老设备 SharedPreferences 里存的是旧预设（不含 tags 字段，AI 不会返回标签），
/// 启动时检测并自动迁移。仅匹配旧预设原文，用户自定义提示词不受影响。
// 注：值引用了 transcriptionPromptPresets 的元素，不能用 const，用 final。
final Map<String, String> legacyPromptMigration = {
  '你是内容转录助手。把用户提供的\$collectionType转录为排版好的 Markdown，去除导航/广告/无关内容，并提取元数据。只输出合法 JSON：{"title":"","content_md":"","author":"","platform":"","published_at":"ISO8601或空字符串"}。published_at 无法确定时输出空字符串。不要输出 JSON 以外的任何字符。platform 值限定为：douyin、xiaoheihe、coolapk、other，不确定填 other。': transcriptionPromptPresets['默认']!,
  '你是内容转录助手。把用户提供的\$collectionType转录为精美的 Markdown。要求：1) 保留原文结构和层次；2) 关键信息加粗或引用；3) 去除所有广告和导航栏；4) 提取标题、作者、发布时间。只输出合法 JSON：{"title":"","content_md":"","author":"","platform":"","published_at":"ISO8601"}。published_at 无法确定时输出空字符串。不要输出 JSON 以外的任何字符。platform 值限定为：douyin、xiaoheihe、coolapk、other，不确定填 other。': transcriptionPromptPresets['默认']!,
  '你是内容转录助手。把用户提供的\$collectionType提取核心要点，用简洁的 Markdown 列表呈现。只输出合法 JSON：{"title":"","content_md":"","author":"","platform":"","published_at":"ISO8601"}。published_at 无法确定时输出空字符串。不要输出 JSON 以外的任何字符。platform 值限定为：douyin、xiaoheihe、coolapk、other，不确定填 other。': transcriptionPromptPresets['精简（1-3 个）']!,
  '你是游戏攻略转录助手。把用户提供的小黑盒帖子转录为排版好的 Markdown，保留攻略步骤、数值数据、配装推荐等关键信息，去除无关评论和广告。只输出合法 JSON：{"title":"","content_md":"","author":"","platform":"xiaoheihe","published_at":"ISO8601"}。published_at 无法确定时输出空字符串。不要输出 JSON 以外的任何字符。': transcriptionPromptPresets['游戏向']!,
  '你是数码内容转录助手。把用户提供的酷安帖子转录为排版好的 Markdown，保留评测要点、使用体验、优缺点对比等关键信息，去除无关评论。只输出合法 JSON：{"title":"","content_md":"","author":"","platform":"coolapk","published_at":"ISO8601"}。published_at 无法确定时输出空字符串。不要输出 JSON 以外的任何字符。': transcriptionPromptPresets['数码向']!,
};

/// 旧版提示词迁移纯函数：把旧版「转录 Markdown」提示词（不含 tags 字段）
/// 替换为对应的新版「仅提取标签」预设；通用检测——要求 content_md
/// 且未要求 "tags" 字段的，一律视为旧版，换成默认预设。其余（含已是
/// 新版的、用户自定义的）原样返回。仅依据 [current] 计算，不做持久化。
String migrateLegacyPrompt(String current) {
  final mapped = legacyPromptMigration[current];
  if (mapped != null && mapped != current) {
    return mapped;
  }
  if (current.contains('content_md') && !current.contains('"tags"')) {
    return _defaultPrompt;
  }
  return current;
}

class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  static const String _kLlmBaseUrl = 'llm_base_url';
  static const String _kLlmApiKey = 'llm_api_key';
  static const String _kLlmModel = 'llm_model';
  static const String _kTranscriptionPrompt = 'transcription_prompt';
  static const String _kDefaultReviewIntervalDays =
      'default_review_interval_days';
  static const String _kHasCompletedOnboarding = 'has_completed_onboarding';
  static const String _kReminderChannels = 'reminder_channels';
  static const String _kSmtpHost = 'smtp_host';
  static const String _kSmtpPort = 'smtp_port';
  static const String _kSmtpSsl = 'smtp_ssl';
  static const String _kSmtpUsername = 'smtp_username';
  static const String _kSmtpPassword = 'smtp_password';
  static const String _kSmtpRecipient = 'smtp_recipient';
  static const String _kDynamicColor = 'dynamic_color';
  static const String _kClipboardDetection = 'clipboard_detection';
  static const String _kThemeMode = 'theme_mode';

  static const String _kSecLlmApiKey = 'sec_llm_api_key';
  static const String _kSecSmtpPassword = 'sec_smtp_password';
  static FlutterSecureStorage? _secureCache;
  FlutterSecureStorage get _secure => _secureCache ??= const FlutterSecureStorage();

  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    // 旧版「转录 Markdown」提示词不含 tags 字段，AI 不会返回标签。
    // 先精确匹配已知旧预设原文；再通用检测：要求 AI 输出 content_md
    // 且未要求 tags 字段的，一律视为旧版转录提示词，自动换成新版
    var prompt = prefs.getString(_kTranscriptionPrompt) ?? _defaultPrompt;
    final migrated = migrateLegacyPrompt(prompt);
    if (migrated != prompt) {
      prompt = migrated;
      await prefs.setString(_kTranscriptionPrompt, migrated);
    }

    // 迁移：从 SharedPreferences 明文 → FlutterSecureStorage 加密存储
    final oldLlmApiKey = prefs.getString(_kLlmApiKey);
    if (oldLlmApiKey != null && oldLlmApiKey.isNotEmpty) {
      await _secure.write(key: _kSecLlmApiKey, value: oldLlmApiKey);
      await prefs.remove(_kLlmApiKey);
    }
    final oldSmtpPassword = prefs.getString(_kSmtpPassword);
    if (oldSmtpPassword != null && oldSmtpPassword.isNotEmpty) {
      await _secure.write(key: _kSecSmtpPassword, value: oldSmtpPassword);
      await prefs.remove(_kSmtpPassword);
    }

    final llmApiKey = await _secure.read(key: _kSecLlmApiKey) ?? '';
    final smtpPassword = await _secure.read(key: _kSecSmtpPassword) ?? '';

    return AppSettings(
      llmBaseUrl: prefs.getString(_kLlmBaseUrl) ?? '',
      llmApiKey: llmApiKey,
      llmModel: prefs.getString(_kLlmModel) ?? '',
      transcriptionPrompt: prompt,
      defaultReviewIntervalDays:
          prefs.getInt(_kDefaultReviewIntervalDays) ?? 1,
      hasCompletedOnboarding:
          prefs.getBool(_kHasCompletedOnboarding) ?? false,
      reminderChannels: _decodeSet(prefs.getString(_kReminderChannels)),
      smtpHost: prefs.getString(_kSmtpHost) ?? '',
      smtpPort: prefs.getInt(_kSmtpPort) ?? 465,
      smtpSsl: prefs.getBool(_kSmtpSsl) ?? true,
      smtpUsername: prefs.getString(_kSmtpUsername) ?? '',
      smtpPassword: smtpPassword,
      smtpRecipient: prefs.getString(_kSmtpRecipient) ?? '',
      dynamicColor: prefs.getBool(_kDynamicColor) ?? true,
      clipboardDetection: prefs.getBool(_kClipboardDetection) ?? true,
      themeMode: prefs.getInt(_kThemeMode) ?? 0,
    );
  }

  Future<void> updateSettings({
    String? llmBaseUrl,
    String? llmApiKey,
    String? llmModel,
    String? transcriptionPrompt,
    int? defaultReviewIntervalDays,
    bool? hasCompletedOnboarding,
    Set<String>? reminderChannels,
    String? smtpHost,
    int? smtpPort,
    bool? smtpSsl,
    String? smtpUsername,
    String? smtpPassword,
    String? smtpRecipient,
    bool? dynamicColor,
    bool? clipboardDetection,
    int? themeMode,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(
      llmBaseUrl: llmBaseUrl,
      llmApiKey: llmApiKey,
      llmModel: llmModel,
      transcriptionPrompt: transcriptionPrompt,
      defaultReviewIntervalDays: defaultReviewIntervalDays,
      hasCompletedOnboarding: hasCompletedOnboarding,
      reminderChannels: reminderChannels,
      smtpHost: smtpHost,
      smtpPort: smtpPort,
      smtpSsl: smtpSsl,
      smtpUsername: smtpUsername,
      smtpPassword: smtpPassword,
      smtpRecipient: smtpRecipient,
      dynamicColor: dynamicColor,
      clipboardDetection: clipboardDetection,
      themeMode: themeMode,
    );
    // 乐观更新：直接下发新值，避免每次写入都闪 loading 导致页面「鬼畜抽动」
    state = AsyncValue.data(updated);
    try {
      await _save(current, updated);
    } catch (e) {
      // 持久化失败时回滚，并原样抛出
      state = AsyncValue.data(current);
      rethrow;
    }
  }

  Future<void> _save(AppSettings current, AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLlmBaseUrl, settings.llmBaseUrl);
    await prefs.setString(_kLlmModel, settings.llmModel);
    await prefs.setString(_kTranscriptionPrompt, settings.transcriptionPrompt);
    await prefs.setInt(
      _kDefaultReviewIntervalDays,
      settings.defaultReviewIntervalDays,
    );
    await prefs.setBool(
      _kHasCompletedOnboarding,
      settings.hasCompletedOnboarding,
    );
    await prefs.setString(
      _kReminderChannels,
      jsonEncode(settings.reminderChannels.toList()),
    );
    await prefs.setString(_kSmtpHost, settings.smtpHost);
    await prefs.setInt(_kSmtpPort, settings.smtpPort);
    await prefs.setBool(_kSmtpSsl, settings.smtpSsl);
    await prefs.setString(_kSmtpUsername, settings.smtpUsername);
    await prefs.setString(_kSmtpRecipient, settings.smtpRecipient);
    await prefs.setBool(_kDynamicColor, settings.dynamicColor);
    await prefs.setBool(_kClipboardDetection, settings.clipboardDetection);
    await prefs.setInt(_kThemeMode, settings.themeMode);

    // 敏感字段：仅在值变化时写入 FlutterSecureStorage
    if (settings.llmApiKey != current.llmApiKey) {
      await _secure.write(key: _kSecLlmApiKey, value: settings.llmApiKey);
    }
    if (settings.smtpPassword != current.smtpPassword) {
      await _secure.write(key: _kSecSmtpPassword, value: settings.smtpPassword);
    }
  }

  Future<void> setThemeMode(ThemeModeValue mode) async {
    await updateSettings(themeMode: mode.value);
  }
}

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
      AppSettingsNotifier.new,
    );
