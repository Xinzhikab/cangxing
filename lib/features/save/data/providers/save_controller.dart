import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/collections/data/providers/category_repository_provider.dart';
import 'package:fav_app/features/collections/data/providers/collection_repository_provider.dart';
import 'package:fav_app/features/collections/data/providers/collections_list_controller.dart';
import 'package:fav_app/features/settings/data/providers/app_settings_provider.dart';
import 'package:fav_app/features/save/data/models/transcription_models.dart';
import 'package:fav_app/features/save/data/providers/transcription_providers.dart';
import 'package:fav_app/features/save/data/services/transcription_service.dart';
import 'package:fav_app/features/save/data/services/web_content_fetcher.dart';

enum SaveUiState { idle, processing, success, failed }

class SaveState {
  final SaveUiState uiState;
  final TranscriptionProgress? progress;
  final TranscriptionFailureReason? failureReason;
  final String? errorMessage;
  final bool saveOnlyRaw;
  final String sourceInput;
  final List<String> log;
  /// 最近一次保存成功的收藏 id，用于转录后编辑元信息
  final String? lastCollectionId;

  const SaveState({
    required this.uiState,
    this.progress,
    this.failureReason,
    this.errorMessage,
    required this.saveOnlyRaw,
    this.sourceInput = '',
    this.log = const [],
    this.lastCollectionId,
  });

  SaveState copyWith({
    SaveUiState? uiState,
    TranscriptionProgress? progress,
    TranscriptionFailureReason? failureReason,
    String? errorMessage,
    bool? saveOnlyRaw,
    String? sourceInput,
    List<String>? log,
    String? lastCollectionId,
  }) {
    return SaveState(
      uiState: uiState ?? this.uiState,
      progress: progress ?? this.progress,
      failureReason: failureReason ?? this.failureReason,
      errorMessage: errorMessage ?? this.errorMessage,
      saveOnlyRaw: saveOnlyRaw ?? this.saveOnlyRaw,
      sourceInput: sourceInput ?? this.sourceInput,
      log: log ?? this.log,
      lastCollectionId: lastCollectionId ?? this.lastCollectionId,
    );
  }
}

class SaveController extends AsyncNotifier<SaveState> {
  @override
  FutureOr<SaveState> build() => const SaveState(
        uiState: SaveUiState.idle,
        saveOnlyRaw: false,
      );

  void _log(String msg) {
    final s = state.valueOrNull;
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final entry = '[$ts] $msg';
    state = AsyncValue.data((s ?? const SaveState(uiState: SaveUiState.idle, saveOnlyRaw: false)).copyWith(log: [...s?.log ?? [], entry]));
  }

  Future<void> save({
    required String rawInput,
    required String type,
    required List<String> categoryPath,
    required bool saveOnlyRaw,
    String? preFetchedContent,
    List<String> preFetchedImages = const [],
    String preFetchedAuthor = '',
    String preFetchedPublishedAt = '',
    String preFetchedTitle = '',
    List<String>? preExtractLog,
    Future<List<String>?> Function(
      List<String> suggestedTags,
      List<String> existingTags,
    )? onConfirmTags,
  }) async {
    state = AsyncValue.data(SaveState(
      uiState: SaveUiState.processing,
      saveOnlyRaw: saveOnlyRaw,
      sourceInput: rawInput,
    ));
    _log('===== 转录开始 =====');
    _log('输入: ${rawInput.length > 100 ? '${rawInput.substring(0, 100)}...' : rawInput}');
    _log('类型: $type | 仅存原文: $saveOnlyRaw | 目录: ${categoryPath.isNotEmpty ? categoryPath.join('/') : '未分类'}');
    // 追加 WebView 提取阶段的日志
    if (preExtractLog != null && preExtractLog.isNotEmpty) {
      _log('--- WebView 提取日志 ---');
      for (final entry in preExtractLog) {
        _log('[提取] $entry');
      }
      _log('--- WebView 提取日志结束 ---');
    }
    try {
      final id = const Uuid().v4();
      final now = DateTime.now();
      final transcribeMode = saveOnlyRaw
          ? TranscribeMode.quickSave
          : (WebContentFetcher.isLikelyUrl(rawInput)
              ? TranscribeMode.fromUrl
              : TranscribeMode.fromPastedText);

      TranscriptionResult? transResult;
      if (!saveOnlyRaw) {
        final llmConfig = ref.read(llmConfigFromSettingsProvider);
        if (llmConfig == null) {
          _log('错误: 未配置 LLM');
          throw const TranscriptionException(
            TranscriptionFailureReason.llmError,
            '未配置 LLM，请先在设置中填写 API Key',
          );
        }
        _log('LLM: ${llmConfig.model} @ ${llmConfig.baseUrl}');
        final svc = ref.read(transcriptionServiceProvider);
        final settings = ref.read(appSettingsProvider).valueOrNull;
        // 已有标签/本地文件夹各取一次，同时用于提示词引导与保存时的归一化
        final existingTags = await _collectExistingTags();
        final existingCategories = await _collectExistingCategories();
        _log('本地文件夹(${existingCategories.length}): ${existingCategories.join('、')}');
        final prompt = _buildPrompt(
          settings?.transcriptionPrompt,
          existingTags,
          existingCategories,
        );
        _log('预提取内容长度: ${preFetchedContent?.length ?? 0} | 预提取图片: ${preFetchedImages.length}');
        _log('预提取作者: $preFetchedAuthor | 日期: $preFetchedPublishedAt | 标题: $preFetchedTitle');
        transResult = await svc.transcribe(
          llmConfig: llmConfig,
          rawInput: rawInput,
          collectionType: type,
          collectionId: id,
          systemPrompt: prompt,
          mode: transcribeMode,
          preFetchedContent: preFetchedContent,
          preFetchedImages: preFetchedImages,
          onProgress: (p) {
            state = AsyncValue.data(state.value!.copyWith(
              progress: p,
              uiState: SaveUiState.processing,
            ));
          },
        );
        // 标签模糊归一化：AI 标签与已有标签模糊匹配时自动替换为已有标签；
        // 文件夹静默归一化：命中本地文件夹则自动使用，不弹窗询问
        final rawAiTags = transResult.tags;
        transResult = transResult.copyWith(
          tags: _normalizeTags(rawAiTags, existingTags),
          category: _normalizeCategory(
              transResult.category, existingCategories),
        );
        if (rawAiTags.join('\u0000') != transResult.tags.join('\u0000')) {
          _log('标签归一化: ${rawAiTags.join(', ')} → ${transResult.tags.join(', ')}');
        }
        _log('AI 转录完成: 标签建议=${transResult.tags.join(', ')}');
        _log('AI 图片本地路径: ${transResult.imageUrls.length} 张');
        // AI 标签仅是建议：弹出确认框让用户勾选，用户取消则中止保存
        if (onConfirmTags != null) {
          final confirmed =
              await onConfirmTags(transResult.tags, existingTags);
          if (confirmed == null) {
            _log('用户在标签确认时取消，中止保存');
            _log('===== 已取消 =====');
            state = AsyncValue.data(state.value!.copyWith(
              uiState: SaveUiState.idle,
            ));
            return;
          }
          _log('用户确认标签: ${confirmed.join(', ')}');
          transResult = transResult.copyWith(tags: confirmed);
        }
      }

      // AI 静默命中的顶层文件夹优先；未命中时回退保存页选择的目录
      final confirmedCategory = transResult?.category ?? '';
      final category = confirmedCategory.isNotEmpty
          ? [confirmedCategory]
          : (categoryPath.isEmpty
              ? [AppConstants.defaultCategoryName]
              : categoryPath);
      // 平台识别：仅按 URL 域名确定性判断，不依赖 AI
      final sourcePlatform = _detectPlatform(rawInput);
      final isUrl = WebContentFetcher.isLikelyUrl(rawInput);
      // 作者/发布时间只用页面抓取的元数据，不采用 AI 结果
      final author = preFetchedAuthor;
      final publishedAt = _parseDate(preFetchedPublishedAt);
      final col = Collection(
        id: id,
        // 标题只用页面精确标题（.section-title__content），无页面标题时兜底
        title: preFetchedTitle.isNotEmpty
            ? preFetchedTitle
            : (isUrl
                ? '来自链接的收藏'
                : (rawInput.length > 30
                    ? '${rawInput.substring(0, 30)}...'
                    : rawInput)),
        type: type,
        sourcePlatform: sourcePlatform,
        sourceUrl: isUrl ? rawInput : '',
        author: author,
        publishedAt: publishedAt,
        collectedAt: now,
        category: category,
        images: transResult?.imageUrls ?? const [],
        tags: transResult?.tags ?? const [],
        note: '',
        // 已读/未读功能已移除：新收藏默认视为已读
        status: CollectionStatus.read,
        reviewDueAt: null,
        rawInput: rawInput,
      );
      final repo = ref.read(collectionRepositoryProvider);
      await repo.create(col, contentMd: transResult?.contentMd ?? '');

      _log('最终保存: 标题="${col.title}" 作者="${col.author}" 平台=$sourcePlatform 日期=${col.publishedAt}');
      _log('最终目录: ${category.join('/')} | 图片: ${col.images.length} 张 | 标签: ${col.tags.join(', ')}');
      _log('===== 转录成功 =====');

      // 日志末尾附 AI 排查信息：思考链 + 原始输出 / 失败原因，
      // 复制日志时一并带走
      final aiReasoning = transResult?.aiReasoning ?? '';
      final aiRaw = transResult?.aiRawOutput ?? '';
      final aiErr = transResult?.aiError ?? '';
      if (aiErr.trim().isNotEmpty) {
        _log('--- AI 调用失败（正文已正常保存） ---');
        _log(aiErr);
      }
      if (aiReasoning.trim().isNotEmpty) {
        _log('--- AI 思考链 ---');
        _log(aiReasoning.length > 3000
            ? '${aiReasoning.substring(0, 3000)}\n……（思考链过长已截断）'
            : aiReasoning);
      }
      if (aiRaw.trim().isNotEmpty) {
        _log('--- AI 原始输出 ---');
        _log(aiRaw);
      }

      if (saveOnlyRaw) {
        await ref.read(fileStorageServiceProvider).saveContent(id, rawInput);
      }

      // 新文章入库后，让列表与统计自动刷新
      ref.invalidate(collectionsListProvider);
      ref.invalidate(groupStatsProvider);
      ref.invalidate(allTagsProvider);
      // 分类浏览页的文章列表是独立 family provider，一并刷新
      ref.invalidate(categoryArticlesProvider);

      state = AsyncValue.data(state.value!.copyWith(
        uiState: SaveUiState.success,
        lastCollectionId: id,
      ));
    } on TranscriptionException catch (e) {
      _log('转录失败: ${e.reason.name} - ${e.message}');
      _log('===== 转录失败，降级保存原文 =====');
      try {
        final id = const Uuid().v4();
        final now = DateTime.now();
        final category = categoryPath.isEmpty
            ? [AppConstants.defaultCategoryName]
            : categoryPath;
        final isUrl = WebContentFetcher.isLikelyUrl(rawInput);
        final col = Collection(
          id: id,
          title: isUrl
              ? '（转录失败）来自链接的收藏'
              : (rawInput.length > 30
                  ? '（转录失败）${rawInput.substring(0, 30)}...'
                  : '（转录失败）未命名收藏'),
          type: type,
          sourcePlatform: _detectPlatform(rawInput),
          sourceUrl: isUrl ? rawInput : '',
          author: '',
          publishedAt: null,
          collectedAt: now,
          category: category,
          images: const [],
          note: '',
          // 已读/未读功能已移除：降级保存也默认视为已读
          status: CollectionStatus.read,
          reviewDueAt: null,
          rawInput: rawInput,
        );
        final repo = ref.read(collectionRepositoryProvider);
        await repo.create(col, contentMd: rawInput);
        // 降级保存的收藏也记录 id，允许用户事后编辑补全元信息
        state = AsyncValue.data(state.value!.copyWith(
          lastCollectionId: id,
        ));
      } catch (_) {}
      state = AsyncValue.data(state.value!.copyWith(
        uiState: SaveUiState.failed,
        failureReason: e.reason,
        errorMessage: e.message,
      ));
    } catch (e) {
      _log('未知错误: $e');
      state = AsyncValue.data(state.value!.copyWith(
        uiState: SaveUiState.failed,
        failureReason: TranscriptionFailureReason.unknown,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> retryLast() async {}

  /// 重置为初始状态。保存页每次进入时调用，清掉上一次的成功/失败条幅
  /// 与日志，避免旧状态残留（SaveController 是全局单例，状态不会自动消失）。
  void reset() {
    state = AsyncValue.data(const SaveState(
      uiState: SaveUiState.idle,
      saveOnlyRaw: false,
    ));
  }

  /// 拼装转录提示词：在末尾追加已有标签与本地文件夹列表，
  /// 引导 AI 优先推荐已有标签、并从本地文件夹中选择 category。
  /// AI 输出仅是建议，最终由用户在确认框勾选。
  String? _buildPrompt(
    String? base,
    List<String> tags,
    List<String> categories,
  ) {
    if (tags.isEmpty && categories.isEmpty) return base;
    final buf = StringBuffer(base ?? '');
    if (tags.isNotEmpty) {
      buf.write('\n\n已有标签：${tags.join('、')}。tags 优先从这个列表中挑选与内容'
          '相关的标签；仅当列表中确实没有相关标签时才建议新标签。');
    }
    if (categories.isNotEmpty) {
      buf.write('\n\n本地文件夹（只能从中选择，禁止编造新文件夹）：${categories.join('、')}。'
          '在 JSON 中额外输出 "category" 字段：从上述文件夹中选出与内容最匹配的一个，'
          '只填文件夹名；没有合适的输出 ""。');
    } else {
      buf.write('\n\n本地没有文件夹："category" 字段输出 ""。');
    }
    return buf.toString();
  }

  /// 标签模糊归一化：AI 生成的标签与已有标签模糊匹配时，自动替换为已有标签，
  /// 避免「地平线4」/「极限竞速地平线4」这类变体标签越攒越多。
  ///
  /// 匹配规则（按优先级）：
  /// 1. 忽略大小写与首尾空白后完全一致 → 替换；
  /// 2. 互相包含（如 AI「地平线4」⊂ 已有「极限竞速地平线4」）且较短方
  ///    长度 ≥2、较短方不短于较长方的 50% → 替换（比例限制防止「游戏」
  ///    这类泛词误吞并长标签）；
  /// 3. 无匹配 → 保留 AI 原词（作为新标签候选，用户在确认框可剔除）。
  static List<String> _normalizeTags(
    List<String> aiTags,
    List<String> existingTags,
  ) {
    // 小写键 → 已有标签原名
    final byKey = <String, String>{};
    for (final e in existingTags) {
      final k = e.trim().toLowerCase();
      if (k.isNotEmpty) byKey.putIfAbsent(k, () => e);
    }
    final out = <String>[];
    for (final raw in aiTags) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      final k = t.toLowerCase();
      // 1) 忽略大小写完全一致
      final exact = byKey[k];
      if (exact != null) {
        if (!out.contains(exact)) out.add(exact);
        continue;
      }
      // 2) 互相包含（带长度护栏）
      String? contained;
      for (final entry in byKey.entries) {
        final ek = entry.key;
        final shorter = ek.length < k.length ? ek : k;
        final longer = ek.length < k.length ? k : ek;
        if (shorter.length >= 2 &&
            shorter.length * 2 >= longer.length &&
            longer.contains(shorter)) {
          contained = entry.value;
          break;
        }
      }
      if (contained != null) {
        if (!out.contains(contained)) out.add(contained);
        continue;
      }
      // 3) 未匹配 → 保留 AI 原词，作为新标签候选
      if (!out.contains(t)) out.add(t);
    }
    return out;
  }

  /// 汇总已有标签：标签注册表 + 全部收藏中已出现的标签，按名称排序。
  Future<List<String>> _collectExistingTags() async {
    final repo = ref.read(collectionRepositoryProvider);
    final names = <String>{...await repo.listTags()};
    try {
      final cols = await repo.list();
      for (final c in cols) {
        names.addAll(c.tags);
      }
    } catch (_) {}
    final list = names.toList()..sort();
    return list.length > 80 ? list.sublist(0, 80) : list;
  }

  /// 汇总本地顶层文件夹名：AI 文件夹建议只能从中选择，绝不新建文件夹。
  /// 两个来源合并：
  /// 1. categories 表（分类管理页创建的文件夹）；
  /// 2. 全部收藏实际使用的顶层文件夹（编辑/移动等操作可能写入
  ///    未在表中注册的路径，只看表会漏掉这些「已有收藏夹」）。
  Future<List<String>> _collectExistingCategories() async {
    final names = <String>{};
    try {
      final cats = await ref.read(categoryRepositoryProvider).listAll();
      for (final c in cats) {
        if (c.parentId == null) {
          final n = c.name.trim();
          if (n.isNotEmpty) names.add(n);
        }
      }
    } catch (_) {}
    try {
      final cols = await ref.read(collectionRepositoryProvider).list();
      for (final c in cols) {
        if (c.category.isNotEmpty) {
          final n = c.category.first.trim();
          if (n.isNotEmpty) names.add(n);
        }
      }
    } catch (_) {}
    final list = names.toList()..sort();
    return list;
  }

  /// 文件夹归一化：与标签不同，AI 建议的文件夹必须命中本地已有文件夹，
  /// 未命中直接丢弃（返回空串，回退保存页选择的目录），不生成新文件夹。
  ///
  /// 匹配规则：
  /// 1. 忽略大小写与首尾空白后完全一致 → 命中；
  /// 2. 互相包含且较短方长度 ≥2（防单字误匹配）→ 命中；
  /// 3. 无匹配 → 空串。
  static String _normalizeCategory(
    String aiCategory,
    List<String> existingCategories,
  ) {
    final t = aiCategory.trim();
    if (t.isEmpty || existingCategories.isEmpty) return '';
    final k = t.toLowerCase();
    for (final e in existingCategories) {
      if (e.toLowerCase() == k) return e;
    }
    for (final e in existingCategories) {
      final ek = e.toLowerCase();
      final shorter = ek.length < k.length ? ek : k;
      if (shorter.length >= 2 &&
          (ek.contains(k) || k.contains(ek)) &&
          shorter.length * 2 >= (ek.length < k.length ? k : ek).length) {
        return e;
      }
    }
    return '';
  }

  /// 平台识别：仅按 URL 域名确定性判断，不依赖 AI。
  static String _detectPlatform(String rawInput) {
    final host = Uri.tryParse(rawInput.trim())?.host.toLowerCase() ?? '';
    if (host.contains('xiaoheihe')) return SourcePlatform.xiaoheihe;
    if (host.contains('douyin')) return SourcePlatform.douyin;
    if (host.contains('coolapk')) return SourcePlatform.coolapk;
    return SourcePlatform.other;
  }

  /// 解析页面抓取的发布时间字符串：支持 2026-08-02 与 08-02（补当前年份）。
  /// 明显不合理（年份过小，如 LLM/页面误给的 1970 占位）返回 null。
  static DateTime? _parseDate(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    DateTime? d;
    final full = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(t);
    if (full != null) {
      d = DateTime.tryParse(
        '${full.group(1)}-${full.group(2)}-${full.group(3)}',
      );
    } else {
      final short = RegExp(r'^(\d{2})-(\d{2})').firstMatch(t);
      if (short != null) {
        final year = DateTime.now().year;
        d = DateTime.tryParse('$year-${short.group(1)}-${short.group(2)}');
      }
    }
    if (d == null || d.year < 2000 || d.year > 2100) return null;
    return d;
  }

  void toggleSaveOnlyRaw(bool value) {
    final s = state.valueOrNull ??
        const SaveState(
          uiState: SaveUiState.idle,
          saveOnlyRaw: false,
        );
    state = AsyncValue.data(s.copyWith(saveOnlyRaw: value));
  }
}

final saveControllerProvider =
    AsyncNotifierProvider<SaveController, SaveState>(SaveController.new);
