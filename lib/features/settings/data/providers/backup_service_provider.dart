import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fav_app/core/utils/storage_path_provider.dart';
import 'package:fav_app/features/collections/data/services/database_service.dart';
import 'package:fav_app/features/save/data/providers/transcription_providers.dart';
import 'package:fav_app/features/settings/data/services/maintenance_service.dart';
import 'package:fav_app/features/settings/data/services/backup_service.dart';

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    ref.read(storagePathProvider),
    ref.read(databaseServiceProvider),
  );
});
