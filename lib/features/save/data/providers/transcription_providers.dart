import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fav_app/core/utils/storage_path_provider.dart';
import 'package:fav_app/features/collections/data/services/file_storage_service.dart';
import 'package:fav_app/features/settings/data/providers/app_settings_provider.dart';
import 'package:fav_app/features/settings/data/providers/cookie_provider.dart';
import 'package:fav_app/features/save/data/models/transcription_models.dart';
import 'package:fav_app/features/save/data/services/web_content_fetcher.dart';
import 'package:fav_app/features/save/data/services/llm_client.dart';
import 'package:fav_app/features/save/data/services/image_downloader.dart';
import 'package:fav_app/features/save/data/services/transcription_service.dart';

final dioProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));
});

final webContentFetcherProvider = Provider<WebContentFetcher>((ref) {
  final cookieNotifier = ref.watch(cookieListProvider.notifier);
  return WebContentFetcher(
    ref.watch(dioProvider),
    (url) => cookieNotifier.matchForUrl(url),
  );
});

final llmClientProvider = Provider<LlmClient>((ref) {
  return LlmClient(ref.watch(dioProvider));
});

final storagePathProvider = Provider<StoragePathProvider>((ref) {
  return StoragePathProvider();
});

final fileStorageServiceProvider = Provider<FileStorageService>((ref) {
  return FileStorageService(ref.watch(storagePathProvider));
});

final imageDownloaderProvider = Provider<ImageDownloader>((ref) {
  return ImageDownloader(
    ref.watch(dioProvider),
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
