import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fav_app/core/utils/app_logger.dart';
import 'package:fav_app/core/utils/storage_path_provider.dart';
import 'package:fav_app/features/collections/data/services/file_storage_service.dart';
import 'package:fav_app/features/settings/data/providers/app_settings_provider.dart';
import 'package:fav_app/features/settings/data/providers/cookie_provider.dart';
import 'package:fav_app/features/save/data/services/web_content_fetcher.dart';
import 'package:fav_app/features/save/data/services/llm_client.dart';
import 'package:fav_app/features/save/data/services/image_downloader.dart';
import 'package:fav_app/features/save/data/services/transcription_service.dart';

final scraperDioProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));
});

final llmDioProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 60),
  ));
});

final webContentFetcherProvider = Provider<WebContentFetcher>((ref) {
  final cookieNotifier = ref.watch(cookieListProvider.notifier);
  return WebContentFetcher(
    ref.watch(scraperDioProvider),
    (url) => cookieNotifier.matchForUrl(url),
  );
});

final llmClientProvider = Provider<LlmClient>((ref) {
  return LlmClient(ref.watch(llmDioProvider), ref.read(appLoggerProvider));
});

final storagePathProvider = Provider<StoragePathProvider>((ref) {
  return StoragePathProvider();
});

final fileStorageServiceProvider = Provider<FileStorageService>((ref) {
  return FileStorageService(ref.watch(storagePathProvider));
});

final imageDownloaderProvider = Provider<ImageDownloader>((ref) {
  return ImageDownloader(
    ref.watch(scraperDioProvider),
    ref.watch(fileStorageServiceProvider),
  );
});

final transcriptionServiceProvider = Provider<TranscriptionService>((ref) {
  return TranscriptionService(
    ref.watch(webContentFetcherProvider),
    ref.watch(llmClientProvider),
    ref.watch(imageDownloaderProvider),
  );
});

final llmConfigFromSettingsProvider = Provider<LlmConfig?>((ref) {
  final s = ref.watch(appSettingsProvider).valueOrNull;
  if (s == null || s.llmApiKey.isEmpty || s.llmModel.isEmpty) return null;
  return LlmConfig(
    baseUrl: s.llmBaseUrl.isEmpty ? 'https://api.openai.com/v1' : s.llmBaseUrl,
    apiKey: s.llmApiKey,
    model: s.llmModel,
  );
});
