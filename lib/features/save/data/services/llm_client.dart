import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:fav_app/features/save/data/models/transcription_models.dart';

class LlmConfig {
  final String baseUrl;
  final String apiKey;
  final String model;

  const LlmConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });
}

class LlmClient {
  final Dio dio;

  LlmClient(this.dio);

  /// 查询服务商可用模型列表（OpenAI 兼容接口 GET /models）。
  Future<List<String>> fetchModels({
    required LlmConfig config,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final url = config.baseUrl.endsWith('/')
        ? '${config.baseUrl}models'
        : '${config.baseUrl}/models';

    final originalHeaders = Map<String, dynamic>.from(dio.options.headers);
    try {
      dio.options.headers['Authorization'] = 'Bearer ${config.apiKey}';
      final resp = await dio.get<dynamic>(url).timeout(timeout);
      dio.options.headers = originalHeaders;

      final data = resp.data;
      if (data is Map<String, dynamic> && data['data'] is List) {
        final ids = (data['data'] as List)
            .whereType<Map>()
            .map((m) => m['id']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
        ids.sort();
        return ids;
      }
      return [];
    } on TimeoutException {
      dio.options.headers = originalHeaders;
      rethrow;
    } on DioException {
      dio.options.headers = originalHeaders;
      rethrow;
    } catch (e) {
      dio.options.headers = originalHeaders;
      rethrow;
    }
  }

  /// 连通性测试：发送一次最小请求验证 Key / Base URL / 模型可用。
  Future<void> testConnection({
    required LlmConfig config,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final url = config.baseUrl.endsWith('/')
        ? '${config.baseUrl}chat/completions'
        : '${config.baseUrl}/chat/completions';

    final body = {
      'model': config.model,
      'max_tokens': 5,
      'messages': [
        {'role': 'user', 'content': 'hi'},
      ],
    };

    final originalHeaders = Map<String, dynamic>.from(dio.options.headers);
    try {
      dio.options.headers['Authorization'] = 'Bearer ${config.apiKey}';
      dio.options.headers['Content-Type'] = 'application/json';
      final resp = await dio.post<dynamic>(url, data: body).timeout(timeout);
      dio.options.headers = originalHeaders;

      final data = resp.data;
      if (data is Map<String, dynamic> &&
          data['choices'] is List &&
          (data['choices'] as List).isNotEmpty) {
        return;
      }
      throw DioException(
        requestOptions: RequestOptions(path: url),
        response: Response(
          requestOptions: RequestOptions(path: url),
          statusCode: resp.statusCode,
        ),
        type: DioExceptionType.badResponse,
        message: '返回结构异常',
      );
    } on TimeoutException {
      dio.options.headers = originalHeaders;
      rethrow;
    } on DioException {
      dio.options.headers = originalHeaders;
      rethrow;
    } catch (e) {
      dio.options.headers = originalHeaders;
      rethrow;
    }
  }

  /// 多轮对话：messages 为 OpenAI 格式（role/content），
  /// 返回助手回复文本。用于文章页「与 AI 对话」等场景。
  Future<String> chat({
    required LlmConfig config,
    required List<Map<String, String>> messages,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final url = config.baseUrl.endsWith('/')
        ? '${config.baseUrl}chat/completions'
        : '${config.baseUrl}/chat/completions';

    final body = {
      'model': config.model,
      'messages': messages,
    };

    final originalHeaders = Map<String, dynamic>.from(dio.options.headers);
    try {
      dio.options.headers['Authorization'] = 'Bearer ${config.apiKey}';
      dio.options.headers['Content-Type'] = 'application/json';
      final resp = await dio.post<dynamic>(
        url,
        data: body,
        options: Options(
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      ).timeout(timeout);
      dio.options.headers = originalHeaders;

      final data = resp.data;
      if (data is Map<String, dynamic> &&
          data['choices'] is List &&
          (data['choices'] as List).isNotEmpty) {
        final msg = (data['choices'] as List)[0];
        if (msg is Map && msg['message'] is Map) {
          return (msg['message'] as Map)['content']?.toString() ?? '';
        }
      }
      throw DioException(
        requestOptions: RequestOptions(path: url),
        type: DioExceptionType.badResponse,
        message: '返回结构异常',
      );
    } on TimeoutException {
      dio.options.headers = originalHeaders;
      rethrow;
    } on DioException {
      dio.options.headers = originalHeaders;
      rethrow;
    } catch (e) {
      dio.options.headers = originalHeaders;
      rethrow;
    }
  }

  Future<TranscriptionResult> transcribe({
    required LlmConfig config,
    required String rawText,
    required String collectionType,
    String? systemPrompt,
    // 长文 + 图片列表转录耗时长，默认给足 90 秒
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final url = config.baseUrl.endsWith('/')
        ? '${config.baseUrl}chat/completions'
        : '${config.baseUrl}/chat/completions';

    final system = (systemPrompt ?? _defaultSystemPrompt)
        .replaceAll(r'$collectionType', collectionType);

    final body = {
      'model': config.model,
      'temperature': 0,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': rawText},
      ],
    };

    final originalHeaders = Map<String, dynamic>.from(dio.options.headers);

    try {
      dio.options.headers['Authorization'] = 'Bearer ${config.apiKey}';
      dio.options.headers['Content-Type'] = 'application/json';

      final resp = await dio.post(
        url,
        data: body,
        // 覆盖全局 30s 接收超时，长文转录响应间隙可能超过 30s
        options: Options(
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      ).timeout(timeout);

      dio.options.headers = originalHeaders;

      if (resp.data == null ||
          resp.data['choices'] == null ||
          resp.data['choices'].isEmpty ||
          resp.data['choices'][0]['message'] == null) {
        throw TranscriptionException(TranscriptionFailureReason.parseError,
            'Invalid LLM response structure');
      }

      final message = resp.data['choices'][0]['message'] as Map<String, dynamic>;
      final content = (message['content'] ?? '').toString();
      // 思考模型（deepseek-reasoner 等）把推理放 reasoning_content，
      // 最终答案才在 content；content 为空时用思考链兜底解析
      final reasoning =
          (message['reasoning_content'] ?? message['reasoning'] ?? '').toString();

      Map<String, dynamic>? json;
      String? parseErr;
      try {
        json = jsonDecode(content) as Map<String, dynamic>;
      } catch (e) {
        parseErr = '$e';
        final fallbackSource = content.trim().isNotEmpty ? content : reasoning;
        final m = RegExp(r'\{[\s\S]*\}')
            .firstMatch(fallbackSource);
        if (m != null) {
          try {
            json = jsonDecode(m.group(0)!) as Map<String, dynamic>;
          } catch (_) {}
        }
      }
      if (json == null) {
        final snippet = (content.trim().isNotEmpty ? content : reasoning);
        throw TranscriptionException(
          TranscriptionFailureReason.parseError,
          'AI 输出解析失败（$parseErr）。原始输出: '
              '${snippet.length > 600 ? snippet.substring(0, 600) : snippet}',
        );
      }

      final result = TranscriptionResult(
        title: json['title'] as String? ?? '',
        contentMd: '',
        author: json['author'] as String? ?? '',
        platform: json['platform'] as String? ?? 'other',
        publishedAt:
            TranscriptionResult.parsePublishedAt(json['published_at'] as String?),
        imageUrls: const [],
        tags: ((json['tags'] as List<dynamic>?) ?? const [])
            .whereType<String>()
            .where((t) => t.trim().isNotEmpty)
            .take(10)
            .toList(growable: false),
        // AI 建议的文件夹：保存层归一化（仅命中本地已有才用）
        category: (json['category'] as String? ?? '').trim(),
        aiReasoning: reasoning,
        aiRawOutput: content,
      );

      return result;
    } on TimeoutException {
      dio.options.headers = originalHeaders;
      throw TranscriptionException(
        TranscriptionFailureReason.timeout,
        'LLM 请求超时，内容可能过长，可重试或选择更精简的提示词',
      );
    } on DioException catch (e) {
      dio.options.headers = originalHeaders;
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        throw TranscriptionException(
          TranscriptionFailureReason.timeout,
          'LLM 请求超时，内容可能过长，可重试或选择更精简的提示词',
        );
      }
      if (e.response != null &&
          e.response!.statusCode != null &&
          e.response!.statusCode! >= 500) {
        throw TranscriptionException(
            TranscriptionFailureReason.llmError, 'Server error');
      }
      throw TranscriptionException(
          TranscriptionFailureReason.network, e.message ?? 'Dio error');
    } on TranscriptionException {
      dio.options.headers = originalHeaders;
      rethrow;
    } catch (e) {
      dio.options.headers = originalHeaders;
      throw TranscriptionException(
          TranscriptionFailureReason.parseError, e.toString());
    }
  }
}

const String _defaultSystemPrompt = '你是标签提取助手。阅读用户提供的文章内容，仅提取主题标签；正文、标题、作者、时间等均由页面提取，不要 AI 生成。只输出合法 JSON：{"tags":["关键词1","关键词2"]}。tags 提取 3-6 个简短主题关键词。不要输出 JSON 以外的任何字符。';
