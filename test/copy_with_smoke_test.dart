import 'package:flutter_test/flutter_test.dart';
import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/features/collections/data/models/collection.dart';
import 'package:fav_app/features/settings/data/models/app_settings.dart';
import 'package:fav_app/features/settings/data/providers/app_settings_provider.dart';
import 'package:fav_app/features/settings/data/providers/list_field_style_provider.dart';
import 'package:fav_app/features/settings/data/providers/reading_style_provider.dart';
import 'package:fav_app/features/collections/data/providers/collections_list_controller.dart';

void main() {
  test('Collection.copyWith covers all fields', () {
    final base = Collection(
      id: 'base_id',
      title: 'base_title',
      type: CollectionEnums.typeToSql(CollectionType.article)!,
      sourcePlatform: CollectionEnums.platformToSql(SourcePlatform.other)!,
      sourceUrl: 'https://example.com',
      author: 'base_author',
      publishedAt: DateTime(2024, 1, 1),
      collectedAt: DateTime(2024, 2, 2),
      category: const ['cat1'],
      images: const ['img1'],
      tags: const ['tag1'],
      note: 'base_note',
      status: CollectionEnums.statusToSql(CollectionStatus.read)!,
      reviewDueAt: DateTime(2024, 3, 3),
      rawInput: 'base_raw',
      contentMd: 'base_md',
    );

    expect(base.copyWith(id: 'S').id, 'S');
    expect(base.copyWith(title: 'T').title, 'T');
    expect(base.copyWith(type: CollectionEnums.typeToSql(CollectionType.comment)!).type,
        CollectionEnums.typeToSql(CollectionType.comment)!);
    expect(base.copyWith(sourcePlatform: CollectionEnums.platformToSql(SourcePlatform.douyin)!).sourcePlatform,
        CollectionEnums.platformToSql(SourcePlatform.douyin)!);
    expect(base.copyWith(sourceUrl: 'U').sourceUrl, 'U');
    expect(base.copyWith(author: 'A').author, 'A');
    expect(base.copyWith(publishedAt: DateTime(2025)).publishedAt!.year, 2025);
    expect(base.copyWith(collectedAt: DateTime(2026)).collectedAt.year, 2026);
    expect(base.copyWith(category: ['new_cat']).category, ['new_cat']);
    expect(base.copyWith(images: ['new_img']).images, ['new_img']);
    expect(base.copyWith(tags: ['new_tag']).tags, ['new_tag']);
    expect(base.copyWith(note: 'N').note, 'N');
    expect(base.copyWith(status: CollectionEnums.statusToSql(CollectionStatus.learning)!).status,
        CollectionEnums.statusToSql(CollectionStatus.learning)!);
    expect(base.copyWith(reviewDueAt: DateTime(2027)).reviewDueAt!.year, 2027);
    expect(base.copyWith(rawInput: 'R').rawInput, 'R');
    expect(base.copyWith(contentMd: 'M').contentMd, 'M');
  });

  test('AppSettings.copyWith covers all fields', () {
    final base = AppSettings(
      llmBaseUrl: 'base_url',
      llmApiKey: 'base_key',
      llmModel: 'base_model',
      transcriptionPrompt: 'base_prompt',
      defaultReviewIntervalDays: 1,
      hasCompletedOnboarding: false,
      reminderChannels: {'local'},
      smtpHost: 'base_host',
      smtpPort: 465,
      smtpSsl: true,
      smtpUsername: 'base_user',
      smtpPassword: 'base_pass',
      smtpRecipient: 'base_recp',
      dynamicColor: true,
      clipboardDetection: true,
    );

    expect(base.copyWith(llmBaseUrl: 'S').llmBaseUrl, 'S');
    expect(base.copyWith(llmApiKey: 'K').llmApiKey, 'K');
    expect(base.copyWith(llmModel: 'M').llmModel, 'M');
    expect(base.copyWith(transcriptionPrompt: 'P').transcriptionPrompt, 'P');
    expect(base.copyWith(defaultReviewIntervalDays: 7).defaultReviewIntervalDays, 7);
    expect(base.copyWith(hasCompletedOnboarding: true).hasCompletedOnboarding, true);
    expect(base.copyWith(reminderChannels: {'email'}).reminderChannels, {'email'});
    expect(base.copyWith(smtpHost: 'H').smtpHost, 'H');
    expect(base.copyWith(smtpPort: 587).smtpPort, 587);
    expect(base.copyWith(smtpSsl: false).smtpSsl, false);
    expect(base.copyWith(smtpUsername: 'U').smtpUsername, 'U');
    expect(base.copyWith(smtpPassword: 'P').smtpPassword, 'P');
    expect(base.copyWith(smtpRecipient: 'R').smtpRecipient, 'R');
    expect(base.copyWith(dynamicColor: false).dynamicColor, false);
    expect(base.copyWith(clipboardDetection: false).clipboardDetection, false);
  });

  test('ListFieldStyle.copyWith covers all fields', () {
    const base = ListFieldStyle(
      showIcon: true,
      showPlatform: true,
      showAuthor: true,
      showTime: true,
      showCategory: false,
      showTags: false,
      showSnippet: false,
      showStatusBadge: true,
      titleLines: 1,
      compact: false,
    );

    expect(base.copyWith(showIcon: false).showIcon, false);
    expect(base.copyWith(showPlatform: false).showPlatform, false);
    expect(base.copyWith(showAuthor: false).showAuthor, false);
    expect(base.copyWith(showTime: false).showTime, false);
    expect(base.copyWith(showCategory: true).showCategory, true);
    expect(base.copyWith(showTags: true).showTags, true);
    expect(base.copyWith(showSnippet: true).showSnippet, true);
    expect(base.copyWith(showStatusBadge: false).showStatusBadge, false);
    expect(base.copyWith(titleLines: 3).titleLines, 3);
    expect(base.copyWith(compact: true).compact, true);
  });

  test('ReadingStyle.copyWith covers all fields', () {
    const base = ReadingStyle(fontSize: 15, lineHeight: 1.6, pagePadding: 16);

    expect(base.copyWith(fontSize: 20).fontSize, 20);
    expect(base.copyWith(lineHeight: 2.0).lineHeight, 2.0);
    expect(base.copyWith(pagePadding: 24).pagePadding, 24);
  });

  test('CollectionsFilter.copyWith covers all fields', () {
    const base = CollectionsFilter(
      keyword: 'k',
      categoryPath: ['c'],
      platform: SourcePlatform.other,
      author: 'a',
      status: CollectionStatus.read,
      sortBy: CollectionSortField.collectedAt,
      descending: true,
    );

    expect(base.copyWith(keyword: 'K').keyword, 'K');
    expect(base.copyWith(categoryPath: ['C']).categoryPath, ['C']);
    expect(base.copyWith(platform: SourcePlatform.douyin).platform, SourcePlatform.douyin);
    expect(base.copyWith(author: 'A').author, 'A');
    expect(base.copyWith(status: CollectionStatus.learning).status, CollectionStatus.learning);
    expect(base.copyWith(sortBy: CollectionSortField.title).sortBy, CollectionSortField.title);
    expect(base.copyWith(descending: false).descending, false);
  });
}
