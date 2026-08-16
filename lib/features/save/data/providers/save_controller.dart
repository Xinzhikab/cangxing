import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/core/utils/app_logger.dart';
import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/collections/data/providers/category_repository_provider.dart';
import 'package:fav_app/features/collections/data/providers/collection_repository_provider.dart';
import 'package:fav_app/features/collections/data/providers/collections_list_controller.dart';
import 'package:fav_app/features/save/data/services/llm_client.dart';
import 'package:fav_app/features/settings/data/providers/app_settings_provider.dart';
import 'package:fav_app/features/save/data/models/transcription_models.dart';
import 'package:fav_app/features/save/data/providers/transcription_providers.dart';
import 'package:fav_app/features/save/data/services/transcription_service.dart';
import 'package:fav_app/features/save/data/services/web_content_fetcher.dart';
import 'package:fav_app/features/save/data/utils/normalize_utils.dart';

enum SaveUiState { idle, processing, success, failed, cancelled }

class SaveState {
  final SaveUiState uiState;
  final TranscriptionProgress? progress;
  final TranscriptionFailureReason? failureReason;
  final String? errorMessage;
  final bool saveOnlyRaw;
  final String sourceInput;
  final List<String> log;
  final List<String> failedImageUrls;
  final String? lastCollectionId;

  const SaveState({
    required this.uiState,
    this.progress,
    this.failureReason,
    this.errorMessage,
    required this.saveOnlyRaw,
    this.sourceInput = '',
    this.log = const [],
    this.failedImageUrls = const [],
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
    List<String>? failedImageUrls,
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
      failedImageUrls: failedImageUrls ?? this.failedImageUrls,
      lastCollectionId: lastCollectionId ?? this.lastCollectionId,
    );
  }
}

class _AiContext {
  final LlmConfig llmConfig;
  final List<String> existingTags;
  final List<String> existingCategories;
  final String? prompt;
  const _AiContext({
    required this.llmConfig,
    required this.existingTags,
    required this.existingCategories,
    this.prompt,
  });
}

class _LastSaveArgs {
  final String rawInput;
  final String type;
  final List<String> categoryPath;
  final bool saveOnlyRaw;
  final String? preFetchedContent;
  final List<String> preFetchedImages;
  final String preFetchedAuthor;
  final String preFetchedPublishedAt;
  final String preFetchedTitle;
  final List<String>? preExtractLog;
  const _LastSaveArgs({
    required this.rawInput,
    required this.type,
    required this.categoryPath,
    required this.saveOnlyRaw,
    this.preFetchedContent,
    this.preFetchedImages = const [],
    this.preFetchedAuthor = '',
    this.preFetchedPublishedAt = '',
    this.preFetchedTitle = '',
    this.preExtractLog,
  });
}

class SaveController extends AutoDisposeAsyncNotifier<SaveState> {
  bool _cancelled = false;
  _LastSaveArgs? _lastArgs;
  late final AppLogger _logger;

  @override
  FutureOr<SaveState> build() {
    _logger = ref.read(appLoggerProvider);
    return const SaveState(
      uiState: SaveUiState.idle,
      saveOnlyRaw: false,
    );
  }

  void _log(String msg) {
    final s = state.valueOrNull;
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final entry = '[$ts] $msg';
    _logger.info('SaveUI', msg);
    state = AsyncValue.data((s ?? const SaveState(uiState: SaveUiState.idle, saveOnlyRaw: false)).copyWith(log: [...s?.log ?? [], entry]));
  }

  void cancel() {
    _cancelled = true;
    final s = state.valueOrNull;
    if (s != null && s.uiState == SaveUiState.processing) {
      _log('===== 已取消 =====');
      state = AsyncValue.data(s.copyWith(uiState: SaveUiState.cancelled));
    }
  }

  bool get _checkCancelled {
    if (_cancelled) {
      _logger.info('SaveController', 'cancelled by user, abort');
      return true;
    }
    return false;
  }

  Future<_AiContext?> _prepareAiContext(
    String rawInput,
    String type,
  ) async {
    if (_checkCancelled) return null;
    final llmConfig = ref.read(llmConfigFromSettingsProvider);
    if (llmConfig == null) {
      _log('错误: 未配置 LLM');
      throw const TranscriptionException(
        TranscriptionFailureReason.llmError,
        '未配置 LLM，请先在设置中填写 API Key',
      );
    }
    _log('LLM: ${llmConfig.model} @ ${llmConfig.baseUrl}');
    final existingTags = await _collectExistingTags();
    if (_checkCancelled) return null;
    final existingCategories = await _collectExistingCategories();
    if (_checkCancelled) return null;
    _log('本地文件夹(${existingCategories.length}): ${existingCategories.join('、')}');
    final settings = ref.read(appSettingsProvider).valueOrNull;
    final prompt = _buildPrompt(
      settings?.transcriptionPrompt,
      existingTags,
      existingCategories,
    );
    return _AiContext(
      llmConfig: llmConfig,
      existingTags: existingTags,
      existingCategories: existingCategories,
      prompt: prompt,
    );
  }

  Future<TranscriptionResult?> _runAiNormalization({
    required _AiContext ctx,
    required String rawInput,
    required String type,
    required String collectionId,
    required TranscribeMode mode,
    String? preFetchedContent,
    List<String> preFetchedImages = const [],
    Future<List<String>?> Function(List<String>, List<String>)? onConfirmTags,
  }) async {
    final svc = ref.read(transcriptionServiceProvider);
    _log('预提取内容长度: ${preFetchedContent?.length ?? 0} | 预提取图片: ${preFetchedImages.length}');
    final transResult = await svc.transcribe(
      llmConfig: ctx.llmConfig,
      rawInput: rawInput,
      collectionType: type,
      collectionId: collectionId,
      systemPrompt: ctx.prompt,
      mode: mode,
      preFetchedContent: preFetchedContent,
      preFetchedImages: preFetchedImages,
      onProgress: (p) {
        state = AsyncValue.data(state.value!.copyWith(
          progress: p,
          uiState: SaveUiState.processing,
        ));
      },
      onImageDownloadFailed: (urls) {
        state = AsyncValue.data(state.value!.copyWith(failedImageUrls: urls));
        _log('⚠️ ${urls.length} 张图片下载失败：${urls.take(3).join('、')}${urls.length > 3 ? ' 等' : ''}');
      },
    );
    if (_checkCancelled) return null;
    final rawAiTags = transResult.tags;
    final normalized = transResult.copyWith(
      tags: normalizeTags(rawAiTags, ctx.existingTags),
      category: normalizeCategory(transResult.category, ctx.existingCategories),
    );
    if (rawAiTags.join('\u0000') != normalized.tags.join('\u0000')) {
      _log('标签归一化: ${rawAiTags.join(', ')} → ${normalized.tags.join(', ')}');
    }
    _log('AI 转录完成: 标签建议=${normalized.tags.join(', ')}');
    _log('AI 图片本地路径: ${normalized.imageUrls.length} 张');
    if (onConfirmTags != null) {
      final confirmed = await onConfirmTags(normalized.tags, ctx.existingTags);
      if (_checkCancelled) return null;
      if (confirmed == null) {
        _log('用户在标签确认时取消，中止保存');
        _log('===== 已取消 =====');
        state = AsyncValue.data(state.value!.copyWith(uiState: SaveUiState.idle));
        return null;
      }
      _log('用户确认标签: ${confirmed.join(', ')}');
      return normalized.copyWith(tags: confirmed);
    }
    return normalized;
  }

  Collection _assembleCollection({
    required String id,
    required DateTime now,
    required String rawInput,
    required String type,
    required List<String> categoryPath,
    required String preFetchedAuthor,
    required String preFetchedPublishedAt,
    required String preFetchedTitle,
    TranscriptionResult? transResult,
  }) {
    final confirmedCategory = transResult?.category ?? '';
    final category = confirmedCategory.isNotEmpty
        ? [confirmedCategory]
        : (categoryPath.isEmpty ? [AppConstants.defaultCategoryName] : categoryPath);
    final sourcePlatform = _detectPlatform(rawInput);
    final isUrl = WebContentFetcher.isLikelyUrl(rawInput);
    final author = preFetchedAuthor;
    final publishedAt = _parseDate(preFetchedPublishedAt);
    return Collection(
      id: id,
      title: preFetchedTitle.isNotEmpty
          ? preFetchedTitle
          : (isUrl ? '来自链接的收藏' : (rawInput.length > 30 ? '${rawInput.substring(0, 30)}...' : rawInput)),
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
      status: CollectionEnums.statusToSql(CollectionStatus.read)!,
      reviewDueAt: null,
      rawInput: rawInput,
    );
  }

  Future<Collection> _persistToDatabaseAndFs({
    required Collection col,
    required String contentMd,
    required bool saveOnlyRaw,
    required String rawInput,
    TranscriptionResult? transResult,
  }) async {
    final repo = ref.read(collectionRepositoryProvider);
    await repo.create(col, contentMd: contentMd);
    if (_checkCancelled) return col;
    _log('最终保存: 标题="${col.title}" 作者="${col.author}" 平台=${col.sourcePlatform} 日期=${col.publishedAt}');
    _log('最终目录: ${col.category.join('/')} | 图片: ${col.images.length} 张 | 标签: ${col.tags.join(', ')}');
    _log('===== 转录成功 =====');
    final aiReasoning = transResult?.aiReasoning ?? '';
    final aiRaw = transResult?.aiRawOutput ?? '';
    final aiErr = transResult?.aiError ?? '';
    if (aiErr.trim().isNotEmpty) {
      _log('--- AI 调用失败（正文已正常保存） ---');
      _log(aiErr);
    }
    if (aiReasoning.trim().isNotEmpty) {
      _log('--- AI 思考链 ---');
      _log(aiReasoning.length > 3000 ? '${aiReasoning.substring(0, 3000)}\n……（思考链过长已截断）' : aiReasoning);
    }
    if (aiRaw.trim().isNotEmpty) {
      _log('--- AI 原始输出 ---');
      _log(aiRaw);
    }
    if (saveOnlyRaw) {
      await ref.read(fileStorageServiceProvider).saveContent(col.id, rawInput);
    }
    ref.invalidate(collectionsListProvider);
    ref.invalidate(groupStatsProvider);
    ref.invalidate(allTagsProvider);
    ref.invalidate(categoryArticlesProvider);
    return col;
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
    _cancelled = false;
    _lastArgs = _LastSaveArgs(
      rawInput: rawInput,
      type: type,
      categoryPath: categoryPath,
      saveOnlyRaw: saveOnlyRaw,
      preFetchedContent: preFetchedContent,
      preFetchedImages: preFetchedImages,
      preFetchedAuthor: preFetchedAuthor,
      preFetchedPublishedAt: preFetchedPublishedAt,
      preFetchedTitle: preFetchedTitle,
      preExtractLog: preExtractLog,
    );
    state = AsyncValue.data(SaveState(
      uiState: SaveUiState.processing,
      saveOnlyRaw: saveOnlyRaw,
      sourceInput: rawInput,
      failedImageUrls: const [],
    ));
    _log('===== 转录开始 =====');
    _log('输入: ${rawInput.length > 100 ? '${rawInput.substring(0, 100)}...' : rawInput}');
    _log('类型: $type | 仅存原文: $saveOnlyRaw | 目录: ${categoryPath.isNotEmpty ? categoryPath.join('/') : '未分类'}');
    if (preExtractLog != null && preExtractLog.isNotEmpty) {
      _log('--- WebView 提取日志 ---');
      for (final entry in preExtractLog) { _log('[提取] $entry'); }
      _log('--- WebView 提取日志结束 ---');
    }
    try {
      final id = const Uuid().v4();
      final now = DateTime.now();
      final mode = saveOnlyRaw
          ? TranscribeMode.quickSave
          : (WebContentFetcher.isLikelyUrl(rawInput) ? TranscribeMode.fromUrl : TranscribeMode.fromPastedText);
      TranscriptionResult? transResult;
      if (!saveOnlyRaw) {
        final aiCtx = await _prepareAiContext(rawInput, type);
        if (aiCtx == null) return;
        transResult = await _runAiNormalization(
          ctx: aiCtx,
          rawInput: rawInput,
          type: type,
          collectionId: id,
          mode: mode,
          preFetchedContent: preFetchedContent,
          preFetchedImages: preFetchedImages,
          onConfirmTags: onConfirmTags,
        );
        if (transResult == null && _checkCancelled == false && state.valueOrNull?.uiState == SaveUiState.idle) return;
        if (transResult == null) return;
      }
      if (_checkCancelled) return;
      final col = _assembleCollection(
        id: id, now: now, rawInput: rawInput, type: type,
        categoryPath: categoryPath, preFetchedAuthor: preFetchedAuthor,
        preFetchedPublishedAt: preFetchedPublishedAt, preFetchedTitle: preFetchedTitle,
        transResult: transResult,
      );
      await _persistToDatabaseAndFs(
        col: col, contentMd: transResult?.contentMd ?? '',
        saveOnlyRaw: saveOnlyRaw, rawInput: rawInput, transResult: transResult,
      );
      state = AsyncValue.data(state.value!.copyWith(uiState: SaveUiState.success, lastCollectionId: id));
    } on TranscriptionException catch (e) {
      if (_cancelled) return;
      _log('转录失败: ${e.reason.name} - ${e.message}');
      _log('===== 转录失败，降级保存原文 =====');
      try {
        final id = const Uuid().v4();
        final now = DateTime.now();
        final category = categoryPath.isEmpty ? [AppConstants.defaultCategoryName] : categoryPath;
        final isUrl = WebContentFetcher.isLikelyUrl(rawInput);
        final col = Collection(
          id: id,
          title: isUrl ? '（转录失败）来自链接的收藏' : (rawInput.length > 30 ? '（转录失败）${rawInput.substring(0, 30)}...' : '（转录失败）未命名收藏'),
          type: type, sourcePlatform: _detectPlatform(rawInput),
          sourceUrl: isUrl ? rawInput : '', author: '', publishedAt: null,
          collectedAt: now, category: category, images: const [], note: '',
          status: CollectionEnums.statusToSql(CollectionStatus.read)!, reviewDueAt: null, rawInput: rawInput,
        );
        await ref.read(collectionRepositoryProvider).create(col, contentMd: rawInput);
        state = AsyncValue.data(state.value!.copyWith(lastCollectionId: id));
      } catch (e2, st) {
        _logger.error('SaveController', '降级保存也失败了！ $e2', st);
        rethrow;
      }
      state = AsyncValue.data(state.value!.copyWith(
        uiState: SaveUiState.failed, failureReason: e.reason, errorMessage: e.message,
      ));
    } catch (e) {
      if (_cancelled) return;
      _log('未知错误: $e');
      state = AsyncValue.data(state.value!.copyWith(
        uiState: SaveUiState.failed,
        failureReason: TranscriptionFailureReason.unknown,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> retryLast() async {
    final args = _lastArgs;
    if (args == null) return;
    await save(
      rawInput: args.rawInput,
      type: args.type,
      categoryPath: args.categoryPath,
      saveOnlyRaw: args.saveOnlyRaw,
      preFetchedContent: args.preFetchedContent,
      preFetchedImages: args.preFetchedImages,
      preFetchedAuthor: args.preFetchedAuthor,
      preFetchedPublishedAt: args.preFetchedPublishedAt,
      preFetchedTitle: args.preFetchedTitle,
      preExtractLog: args.preExtractLog,
    );
  }

  /// 重置为初始状态。保存页每次进入时调用，清掉上一次的成功/失败条幅
  /// 与日志，避免旧状态残留（SaveController 是全局单例，状态不会自动消失）。
  void reset() {
    _cancelled = false;
    state = AsyncValue.data(const SaveState(
      uiState: SaveUiState.idle,
      saveOnlyRaw: false,
      failedImageUrls: [],
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

  /// 汇总已有标签：标签注册表 + 全部收藏中已出现的标签，按名称排序。
  Future<List<String>> _collectExistingTags() async {
    final repo = ref.read(collectionRepositoryProvider);
    final names = <String>{...await repo.listTags()};
    try {
      final cols = await repo.list();
      for (final c in cols) {
        names.addAll(c.tags);
      }
    } catch (e, st) {
      _logger.warn('SaveController', 'collectTags: $e', st);
    }
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
    } catch (e, st) {
      _logger.warn('SaveController', 'collectCategories(listAll): $e', st);
    }
    try {
      final cols = await ref.read(collectionRepositoryProvider).list();
      for (final c in cols) {
        if (c.category.isNotEmpty) {
          final n = c.category.first.trim();
          if (n.isNotEmpty) names.add(n);
        }
      }
    } catch (e, st) {
      _logger.warn('SaveController', 'collectCategories(listCols): $e', st);
    }
    final list = names.toList()..sort();
    return list;
  }

  /// 平台识别：仅按 URL 域名确定性判断，不依赖 AI。返回 SQL 层字符串值。
  static String _detectPlatform(String rawInput) {
    final host = Uri.tryParse(rawInput.trim())?.host.toLowerCase() ?? '';
    SourcePlatform p = SourcePlatform.other;
    if (host.contains('xiaoheihe')) p = SourcePlatform.xiaoheihe;
    if (host.contains('douyin')) p = SourcePlatform.douyin;
    if (host.contains('coolapk')) p = SourcePlatform.coolapk;
    return CollectionEnums.platformToSql(p)!;
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
    AsyncNotifierProvider.autoDispose<SaveController, SaveState>(SaveController.new);
