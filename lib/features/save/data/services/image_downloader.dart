import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:fav_app/features/collections/data/services/file_storage_service.dart';

class ImageDownloader {
  final Dio dio;
  final FileStorageService fileStorage;

  ImageDownloader(this.dio, this.fileStorage);

  /// 下载图片到本地。返回与 urls 一一对应的结果列表：
  /// 成功的为本地路径，失败的为 null（避免与占位符错位）。
  ///
  /// 每张图片最多重试 [maxRetries] 次（共 3 次尝试），指数退避间隔
  /// 500ms → 1500ms。失败图片的 URL 通过 [onFailed] 回调返回给调用方，
  /// 便于在保存成功后记录哪些图丢了。
  Future<List<String?>> downloadImages(
    String collectionId,
    List<String> urls, {
    void Function(int current, int total)? onProgress,
    void Function(List<String> failedUrls)? onFailed,
    int maxRetries = 2,
  }) async {
    final result = <String?>[];
    final failed = <String>[];

    for (var i = 0; i < urls.length; i++) {
      try {
        final path = await _downloadWithRetry(
          collectionId,
          i,
          urls[i],
          maxRetries: maxRetries,
        );
        result.add(path);
        if (path == null) failed.add(urls[i]);
      } catch (e) {
        // _downloadWithRetry 内部已兜底异常，这里防御性保底
        result.add(null);
        failed.add(urls[i]);
      } finally {
        onProgress?.call(i + 1, urls.length);
      }
    }

    if (failed.isNotEmpty) onFailed?.call(failed);

    return result;
  }

  /// 单张图片下载，带指数退避重试。
  /// 退避间隔：attempt 0 失败后等 500ms，attempt 1 失败后等 1500ms，
  /// attempt 2（最后一次）失败直接返回 null。
  Future<String?> _downloadWithRetry(
    String collectionId,
    int index,
    String url, {
    int maxRetries = 2,
  }) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final resp = await dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            // 部分图床（如小黑盒 CDN）会拒绝无浏览器标识的请求
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
                      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
              'Referer': _refererFor(url),
            },
          ),
        );
        final bytes = resp.data;
        if (bytes != null) {
          String ext = p.extension(url);
          if (ext.isEmpty) {
            ext = '.jpg';
          }
          final filename = 'img_${(index + 1).toString().padLeft(3, '0')}$ext';
          return await fileStorage.saveImage(collectionId, filename, bytes);
        }
      } catch (e) {
        if (attempt == maxRetries) {
          debugPrint('[ImageDownloader] give up after $maxRetries retries: $url → $e');
          return null;
        }
      }

      if (attempt == maxRetries) {
        debugPrint('[ImageDownloader] give up after $maxRetries retries: $url (empty response)');
        return null;
      }

      final delayMs = 500 * (attempt == 0 ? 1 : 3); // 500, 1500
      await Future.delayed(Duration(milliseconds: delayMs));
      debugPrint('[ImageDownloader] retry ${attempt + 1}/$maxRetries for $url after ${delayMs}ms');
    }
    return null;
  }

  /// 图片域名的根站点作为 Referer，规避防盗链。
  static String _refererFor(String url) {
    try {
      final host = Uri.parse(url).host;
      return 'https://$host/';
    } catch (_) {
      return '';
    }
  }
}
