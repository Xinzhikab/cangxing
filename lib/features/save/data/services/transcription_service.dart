import 'package:flutter/foundation.dart';

import 'package:fav_app/features/save/data/models/transcription_models.dart';
import 'package:fav_app/features/save/data/services/web_content_fetcher.dart';
import 'package:fav_app/features/save/data/services/llm_client.dart';
import 'package:fav_app/features/save/data/services/image_downloader.dart';

enum TranscribeMode { fromUrl, fromPastedText, quickSave }

class TranscriptionService {
  final WebContentFetcher fetcher;
  final LlmClient llmClient;
  final ImageDownloader imageDownloader;

  TranscriptionService(this.fetcher, this.llmClient, this.imageDownloader);

  Future<TranscriptionResult> transcribe({
    required LlmConfig llmConfig,
    required String rawInput,
    required String collectionType,
    required String collectionId,
    String? systemPrompt,
    TranscribeMode mode = TranscribeMode.fromUrl,
    String? preFetchedContent,
    List<String> preFetchedImages = const [],
    void Function(TranscriptionProgress progress)? onProgress,
    void Function(List<String> failedUrls)? onImageDownloadFailed,
  }) async {
    String text;
    List<String> images = const [];
    List<String?> localPaths = const [];

    if (mode == TranscribeMode.quickSave) {
      throw TranscriptionException(
        TranscriptionFailureReason.unknown,
        'quick save should not call transcribe',
      );
    } else if (mode == TranscribeMode.fromUrl) {
      if (preFetchedContent != null && preFetchedContent.trim().isNotEmpty) {
        // 外部已提供（可能是 WebView 渲染提取的）正文，跳过抓取
        text = preFetchedContent;
        images = preFetchedImages;
      } else {
        onProgress?.call(
          const TranscriptionProgress(step: TranscriptionStep.fetching),
        );
        try {
          final fetched = await fetcher.fetch(rawInput);
          text = fetched.text;
          images = fetched.images;
        } catch (e) {
          onProgress?.call(
            TranscriptionProgress(
              step: TranscriptionStep.failed,
              message: '抓取失败，降级为仅保存 URL',
            ),
          );
          rethrow;
        }
      }
    } else {
      text = rawInput;
    }

    // 1. 先用抓取阶段收集的图片地址下载到本地
    if (images.isNotEmpty) {
      onProgress?.call(
        TranscriptionProgress(
          step: TranscriptionStep.downloadingImages,
          current: 0,
          total: images.length,
        ),
      );
      localPaths = await imageDownloader.downloadImages(
        collectionId,
        images,
        onProgress: (c, t) => onProgress?.call(
          TranscriptionProgress(
            step: TranscriptionStep.downloadingImages,
            current: c,
            total: t,
          ),
        ),
        onFailed: (failedUrls) {
          debugPrint('[Transcription] ${failedUrls.length}/${images.length} '
              '图片下载失败（已重试）：${failedUrls.join(", ")}');
          onImageDownloadFailed?.call(failedUrls);
        },
      );
    }

    // 2. AI 只提取标签；标题/作者/平台/时间均由页面提取，不依赖 AI
    onProgress?.call(
      const TranscriptionProgress(step: TranscriptionStep.transcribing),
    );
    TranscriptionResult meta;
    try {
      meta = await llmClient.transcribe(
        config: llmConfig,
        rawText: _buildLlmInput(text),
        collectionType: collectionType,
        systemPrompt: systemPrompt,
      );
    } catch (e) {
      // AI 失败不影响正文保存：标题/标签留空，正文照常保存；
      // 错误原因记入 aiError，由保存层写进转录日志（此前静默吞掉，
      // 日志只见「标签=空」无法排查）
      meta = TranscriptionResult(
        title: '',
        contentMd: '',
        author: '',
        platform: 'other',
        imageUrls: const [],
        aiError: e.toString(),
      );
    }

    // 3. 正文 = 抓取原文，图片占位符替换为本地路径
    final replacedMd = _replacePlaceholders(text, localPaths);

    onProgress?.call(
      const TranscriptionProgress(step: TranscriptionStep.done),
    );

    return meta.copyWith(
      contentMd: replacedMd,
      imageUrls: localPaths.whereType<String>().toList(growable: false),
    );
  }
}

/// 拼装喂给 LLM 的输入：原始正文（截断超长部分），AI 仅用于提取标签。
String _buildLlmInput(String text) {
  const maxChars = 6000;
  var trimmed = text.trim();
  if (trimmed.length > maxChars) {
    trimmed = '${trimmed.substring(0, maxChars)}\n\n……（原文过长已截断）';
  }
  return trimmed;
}

/// 把转录结果中的 [图N] 占位符替换为本地图片路径；
/// 对应图片下载失败（localPaths 中为 null）时，直接移除该占位符。
String _replacePlaceholders(String md, List<String?> localPaths) {
  if (localPaths.isEmpty) return md;
  return md.replaceAllMapped(RegExp(r'\[图(\d+)\]'), (m) {
    final idx = int.tryParse(m.group(1) ?? '');
    if (idx != null && idx >= 1 && idx <= localPaths.length) {
      final path = localPaths[idx - 1];
      if (path != null) return '![图片]($path)';
      return ''; // 下载失败，移除占位符
    }
    return m.group(0)!;
  });
}
