class AppSettings {
  final String llmBaseUrl;
  final String llmApiKey;
  final String llmModel;
  final String transcriptionPrompt;
  final int defaultReviewIntervalDays;
  final bool hasCompletedOnboarding;
  final Set<String> reminderChannels;
  final String smtpHost;
  final int smtpPort;
  final bool smtpSsl;
  final String smtpUsername;
  final String smtpPassword;
  final String smtpRecipient;
  final bool dynamicColor;
  final bool clipboardDetection;
  final int themeMode;

  AppSettings({
    required this.llmBaseUrl,
    required this.llmApiKey,
    required this.llmModel,
    required this.transcriptionPrompt,
    required this.defaultReviewIntervalDays,
    required this.hasCompletedOnboarding,
    required this.reminderChannels,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpSsl,
    required this.smtpUsername,
    required this.smtpPassword,
    required this.smtpRecipient,
    required this.dynamicColor,
    required this.clipboardDetection,
    this.themeMode = 0,
  });

  AppSettings copyWith({
    String? llmBaseUrl,
    String? llmApiKey,
    String? llmModel,
    String? transcriptionPrompt,
    int? defaultReviewIntervalDays,
    bool? hasCompletedOnboarding,
    Set<String>? reminderChannels,
    String? smtpHost,
    int? smtpPort,
    bool? smtpSsl,
    String? smtpUsername,
    String? smtpPassword,
    String? smtpRecipient,
    bool? dynamicColor,
    bool? clipboardDetection,
    int? themeMode,
  }) {
    return AppSettings(
      llmBaseUrl: llmBaseUrl ?? this.llmBaseUrl,
      llmApiKey: llmApiKey ?? this.llmApiKey,
      llmModel: llmModel ?? this.llmModel,
      transcriptionPrompt: transcriptionPrompt ?? this.transcriptionPrompt,
      defaultReviewIntervalDays:
          defaultReviewIntervalDays ?? this.defaultReviewIntervalDays,
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      reminderChannels: reminderChannels ?? this.reminderChannels,
      smtpHost: smtpHost ?? this.smtpHost,
      smtpPort: smtpPort ?? this.smtpPort,
      smtpSsl: smtpSsl ?? this.smtpSsl,
      smtpUsername: smtpUsername ?? this.smtpUsername,
      smtpPassword: smtpPassword ?? this.smtpPassword,
      smtpRecipient: smtpRecipient ?? this.smtpRecipient,
      dynamicColor: dynamicColor ?? this.dynamicColor,
      clipboardDetection: clipboardDetection ?? this.clipboardDetection,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'llmBaseUrl': llmBaseUrl,
      'llmApiKey': llmApiKey,
      'llmModel': llmModel,
      'transcriptionPrompt': transcriptionPrompt,
      'defaultReviewIntervalDays': defaultReviewIntervalDays,
      'hasCompletedOnboarding': hasCompletedOnboarding,
      'reminderChannels': reminderChannels.toList(),
      'smtpHost': smtpHost,
      'smtpPort': smtpPort,
      'smtpSsl': smtpSsl,
      'smtpUsername': smtpUsername,
      'smtpPassword': smtpPassword,
      'smtpRecipient': smtpRecipient,
      'dynamicColor': dynamicColor,
      'clipboardDetection': clipboardDetection,
      'themeMode': themeMode,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      llmBaseUrl: json['llmBaseUrl'] as String? ?? '',
      llmApiKey: json['llmApiKey'] as String? ?? '',
      llmModel: json['llmModel'] as String? ?? '',
      transcriptionPrompt: json['transcriptionPrompt'] as String? ?? '',
      defaultReviewIntervalDays: json['defaultReviewIntervalDays'] as int? ?? 1,
      hasCompletedOnboarding: json['hasCompletedOnboarding'] as bool? ?? false,
      reminderChannels: (json['reminderChannels'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toSet() ??
          {'local'},
      smtpHost: json['smtpHost'] as String? ?? '',
      smtpPort: json['smtpPort'] as int? ?? 465,
      smtpSsl: json['smtpSsl'] as bool? ?? true,
      smtpUsername: json['smtpUsername'] as String? ?? '',
      smtpPassword: json['smtpPassword'] as String? ?? '',
      smtpRecipient: json['smtpRecipient'] as String? ?? '',
      dynamicColor: json['dynamicColor'] as bool? ?? true,
      clipboardDetection: json['clipboardDetection'] as bool? ?? true,
      themeMode: json['themeMode'] as int? ?? 0,
    );
  }
}
