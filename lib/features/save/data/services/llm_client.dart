import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:fav_app/core/utils/app_logger.dart';
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
  final AppLogger _logger;

  LlmClient(this.dio, this._logger);

  String _buildUrl(String base, String endpoint) {
    return base.endsWith('/') ? '$base$endpoint' : '$base/$endpoint';
  }

  Future<Response<T>> _request<T>(
    String method,
    LlmConfig config,
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? extraHeaders,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final url = _buildUrl(config.baseUrl, endpoint);
    final headers = <String, dynamic>{
      'Authorization': 'Bearer ${config.apiKey}',
    };
    if (method == 'POST') {
      headers['Content-Type'] = 'application/json';
    }
    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }
    try {
      final resp = await dio.request<T>(
        url,
        options: Options(
          method: method,
          headers: headers,
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
        data: body,
      ).timeout(timeout);
      return resp;
    } catch (e, st) {
      _logger.error('LlmClient', '$method $endpoint failed: $e', st);
      rethrow;
    }
  }

  Future<Response<T>> _get<T>(
    LlmConfig config,
    String endpoint, {
    Map<String, dynamic>? extraHeaders,
    Duration timeout = const Duration(seconds: 15),
  }) =>
      _request<T>(
        'GET',
        config,
        endpoint,
        extraHeaders: extraHeaders,
        timeout: timeout,
      );

  Future<Response<T>> _post<T>(
    LlmConfig config,
    String endpoint,
    Map<String, dynamic> body, {
    Map<String, dynamic>? extraHeaders,
    Duration timeout = const Duration(seconds: 60),
  }) =>
      _request<T>(
        'POST',
        config,
        endpoint,
        body: body,
        extraHeaders: extraHeaders,
        timeout: timeout,
      );

  Future<List<String>> fetchModels({
    required LlmConfig config,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final resp = await _get<dynamic>(config, 'models', timeout: timeout);
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
  }

  Future<void> testConnection({
    required LlmConfig config,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final body = {
      'model': config.model,
      'max_tokens': 5,
      'messages': [
        {'role': 'user', 'content': 'hi'},
      ],
    };
    final resp = await _post<dynamic>(
      config,
      'chat/completions',
      body,
      timeout: timeout,
    );
    final data = resp.data;
    if (data is Map<String, dynamic> &&
        data['choices'] is List &&
        (data['choices'] as List).isNotEmpty) {
      return;
    }
    throw DioException(
      requestOptions: RequestOptions(path: _buildUrl(config.baseUrl, 'chat/completions')),
      response: Response(
        requestOptions: RequestOptions(path: _buildUrl(config.baseUrl, 'chat/completions')),
        statusCode: resp.statusCode,
      ),
      type: DioExceptionType.badResponse,
      message: '返回结构异常',
    );
  }

  Future<String> chat({
    required LlmConfig config,
    required List<Map<String, String>> messages,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final body = {
      'model': config.model,
      'messages': messages,
    };
    final resp = await _post<dynamic>(
      config,
      'chat/completions',
      body,
      timeout: timeout,
    );
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
      requestOptions: RequestOptions(path: _buildUrl(config.baseUrl, 'chat/completions')),
      type: DioExceptionType.badResponse,
      message: '返回结构异常',
    );
  }

  /// 流式对话，逐 token 返回（SSE）。保留 [chat] 不变以向后兼容。
  Stream<String> chatStream({
    required LlmConfig config,
    required List<Map<String, String>> messages,
    Duration timeout = const Duration(minutes: 5),
  }) async* {
    final url = _buildUrl(config.baseUrl, 'chat/completions');
    final body = {
      'model': config.model,
      'messages': messages,
      'stream': true,
      'temperature': 0.7,
    };

    late final Response<ResponseBody> response;
    try {
      response = await dio.post<ResponseBody>(
        url,
        data: jsonEncode(body),
        options: Options(
          headers: {
            'Authorization': 'Bearer ${config.apiKey}',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          },
          responseType: ResponseType.stream,
          receiveTimeout: timeout,
        ),
      );
    } catch (e, st) {
      _logger.error('LlmClient', 'POST chat/completions stream failed: $e', st);
      rethrow;
    }

    final stream = response.data!.stream;
    String buffer = '';

    await for (final chunk in stream) {
      buffer += utf8.decode(chunk, allowMalformed: true);
      // 规范化行尾，兼容 \r\n / \r
      buffer = buffer.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

      // SSE 事件以空行分隔
      while (true) {
        final idx = buffer.indexOf('\n\n');
        if (idx < 0) break;
        final event = buffer.substring(0, idx);
        buffer = buffer.substring(idx + 2);

        for (final line in event.split('\n')) {
          if (!line.startsWith('data:')) continue;
          final data = line.substring(5).trim();
          if (data.isEmpty) continue;
          if (data == '[DONE]') return;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final delta =
                json['choices']?[0]?['delta']?['content'] as String?;
            if (delta != null && delta.isNotEmpty) {
              yield delta;
            }
          } catch (_) {
            // 跳过无法解析的行
          }
        }
      }
    }
  }

  Future<TranscriptionResult> transcribe({
    required LlmConfig config,
    required String rawText,
    required String collectionType,
    String? systemPrompt,
    Duration timeout = const Duration(seconds: 90),
  }) async {
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

    try {
      final resp = await _post<dynamic>(
        config,
        'chat/completions',
        body,
        timeout: timeout,
      );

      if (resp.data == null ||
          resp.data['choices'] == null ||
          resp.data['choices'].isEmpty ||
          resp.data['choices'][0]['message'] == null) {
        throw TranscriptionException(TranscriptionFailureReason.parseError,
            'Invalid LLM response structure');
      }

      final message = resp.data['choices'][0]['message'] as Map<String, dynamic>;
      final content = (message['content'] ?? '').toString();
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
        category: (json['category'] as String? ?? '').trim(),
        aiReasoning: reasoning,
        aiRawOutput: content,
      );

      return result;
    } on TimeoutException {
      throw TranscriptionException(
        TranscriptionFailureReason.timeout,
        'LLM 请求超时，内容可能过长，可重试或选择更精简的提示词',
      );
    } on DioException catch (e) {
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
      rethrow;
    } catch (e) {
      throw TranscriptionException(
          TranscriptionFailureReason.parseError, e.toString());
    }
  }
}

const String _defaultSystemPrompt = '你是标签提取助手。阅读用户提供的文章内容，仅提取主题标签；正文、标题、作者、时间等均由页面提取，不要 AI 生成。只输出合法 JSON：{"tags":["关键词1","关键词2"]}。tags 提取 3-6 个简短主题关键词。不要输出 JSON 以外的任何字符。';
