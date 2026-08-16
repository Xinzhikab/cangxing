import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/collections/data/providers/collection_repository_provider.dart';
import 'package:fav_app/core/constants/app_constants.dart';

enum LearningGroup { overdue, today, within3Days, later }

LearningGroup _group(DateTime? dueAt, DateTime now) {
  if (dueAt == null) return LearningGroup.later;
  if (dueAt.isBefore(now)) return LearningGroup.overdue;
  final todayStart = DateTime(now.year, now.month, now.day);
  final tomorrow = todayStart.add(const Duration(days: 1));
  final in3 = todayStart.add(const Duration(days: 3));
  if (dueAt.isBefore(tomorrow)) return LearningGroup.today;
  if (dueAt.isBefore(in3)) return LearningGroup.within3Days;
  return LearningGroup.later;
}

final learningQueueProvider =
    FutureProvider<Map<LearningGroup, List<Collection>>>((ref) async {
  final repo = ref.watch(collectionRepositoryProvider);
  final all = await repo.list(status: CollectionStatus.learning);
  final now = DateTime.now();
  final res = <LearningGroup, List<Collection>>{
    for (final g in LearningGroup.values) g: []
  };
  for (final c in all) {
    res[_group(c.reviewDueAt, now)]!.add(c);
  }
  res.forEach((_, list) => list.sort((a, b) =>
      (a.reviewDueAt ?? DateTime(0))
          .compareTo(b.reviewDueAt ?? DateTime(0))));
  return res;
});
