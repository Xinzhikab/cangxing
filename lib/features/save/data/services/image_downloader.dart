import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:fav_app/features/collections/data/services/file_storage_service.dart';

class ImageDownloader {
  final Dio dio;
  final FileStorageService fileStorage;

  ImageDownloader(this.dio, this.fileStorage);

  /// 下载图片到本地。返回与 urls 一一对应的结果列表：
  /// 成功的为本地路径，失败的为 null（避免与占位符错位）。
  Future<List<String?>> downloadImages(
    String collectionId,
    List<String> urls, {
    void Function(int current, int total)? onProgress,
  }) async {
    final result = <String?>[];

    for (var i = 0; i < urls.length; i++) {
      try {
        final url = urls[i];
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
        if (resp.data == null) {
          result.add(null);
        } else {
          final bytes = resp.data!;
          String ext = p.extension(url);
          if (ext.isEmpty) {
            ext = '.jpg';
          }

          final filename = 'img_${(i + 1).toString().padLeft(3, '0')}$ext';
          final savedPath = await fileStorage.saveImage(
            collectionId,
            filename,
            bytes,
          );
          result.add(savedPath);
        }
      } catch (_) {
        result.add(null);
      } finally {
        onProgress?.call(i + 1, urls.length);
      }
    }

    return result;
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
