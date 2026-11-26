enum DraftCategory {
  all('ALL', 'All'),
  movieWise('MOVIE_WISE', 'Movie Wise'),
  top5India('TOP_5_INDIA', 'Top 5 — India'),
  top5Worldwide('TOP_5_WORLDWIDE', 'Top 5 — Worldwide'),
  malayalamTop5('MALAYALAM_TOP_5', 'Malayalam Top 5'),
  tamilTop5('TAMIL_TOP_5', 'Tamil Top 5'),
  teluguTop5('TELUGU_TOP_5', 'Telugu Top 5'),
  kannadaTop5('KANNADA_TOP_5', 'Kannada Top 5'),
  hindiTop5('HINDI_TOP_5', 'Hindi Top 5'),
  bengaliTop5('BENGALI_TOP_5', 'Bengali Top 5'),
  marathiTop5('MARATHI_TOP_5', 'Marathi Top 5'),
  openingDay('OPENING_DAY', 'Opening Day'),
  milestones('MILESTONES', 'Milestones'),
  latestUpdates('LATEST_UPDATES', 'Latest Updates');

  const DraftCategory(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static DraftCategory fromApi(String value) {
    return DraftCategory.values.firstWhere(
      (e) => e.apiValue == value,
      orElse: () => DraftCategory.latestUpdates,
    );
  }
}

enum DraftStatus {
  pendingReview('PENDING_REVIEW', 'Pending Review'),
  edited('EDITED', 'Edited'),
  publishing('PUBLISHING', 'Publishing'),
  published('PUBLISHED', 'Published'),
  failed('FAILED', 'Failed'),
  expired('EXPIRED', 'Expired'),
  cancelled('CANCELLED', 'Cancelled');

  const DraftStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static DraftStatus fromApi(String value) {
    return DraftStatus.values.firstWhere(
      (e) => e.apiValue == value,
      orElse: () => DraftStatus.pendingReview,
    );
  }
}

class PostDraft {
  const PostDraft({
    required this.id,
    required this.category,
    required this.title,
    this.movieId,
    required this.reportingDate,
    required this.generatedText,
    this.editedText,
    required this.hashtags,
    required this.entries,
    this.mainFigureDisplay,
    required this.sourceSummary,
    required this.weightedCharCount,
    required this.isValidLength,
    required this.status,
    this.numericalEditConfirmed = false,
    this.lastError,
    required this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final DraftCategory category;
  final String title;
  final String? movieId;
  final DateTime reportingDate;
  final String generatedText;
  final String? editedText;
  final List<String> hashtags;
  final List<Map<String, dynamic>> entries;
  final String? mainFigureDisplay;
  final String sourceSummary;
  final int weightedCharCount;
  final bool isValidLength;
  final DraftStatus status;
  final bool numericalEditConfirmed;
  final String? lastError;
  final DateTime expiresAt;
  final DateTime createdAt;

  String get effectiveText =>
      (editedText != null && editedText!.trim().isNotEmpty)
          ? editedText!
          : generatedText;

  bool get isActiveInQueue =>
      status == DraftStatus.pendingReview ||
      status == DraftStatus.edited ||
      status == DraftStatus.failed ||
      status == DraftStatus.publishing;

  factory PostDraft.fromJson(Map<String, dynamic> json) {
    return PostDraft(
      id: json['id'] as String,
      category: DraftCategory.fromApi(json['category'] as String),
      title: json['title'] as String,
      movieId: json['movie_id'] as String?,
      reportingDate: DateTime.parse(json['reporting_date'] as String),
      generatedText: json['generated_text'] as String,
      editedText: json['edited_text'] as String?,
      hashtags: List<String>.from(json['hashtags'] ?? const []),
      entries: List<Map<String, dynamic>>.from(json['entries'] ?? const []),
      mainFigureDisplay: json['main_figure_display'] as String?,
      sourceSummary: json['source_summary'] as String? ?? '',
      weightedCharCount: json['weighted_char_count'] as int? ?? 0,
      isValidLength: json['is_valid_length'] as bool? ?? true,
      status: DraftStatus.fromApi(json['status'] as String),
      numericalEditConfirmed: json['numerical_edit_confirmed'] as bool? ?? false,
      lastError: json['last_error'] as String?,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class PublishedPost {
  const PublishedPost({
    required this.id,
    required this.draftId,
    required this.finalText,
    required this.xPostId,
    required this.xUrl,
    required this.category,
    required this.supportingReportIds,
    required this.publishedAt,
  });

  final String id;
  final String draftId;
  final String finalText;
  final String xPostId;
  final String xUrl;
  final DraftCategory category;
  final List<String> supportingReportIds;
  final DateTime publishedAt;

  factory PublishedPost.fromJson(Map<String, dynamic> json) {
    return PublishedPost(
      id: json['id'] as String,
      draftId: json['draft_id'] as String,
      finalText: json['final_text'] as String,
      xPostId: json['x_post_id'] as String,
      xUrl: json['x_url'] as String,
      category: DraftCategory.fromApi(json['category'] as String),
      supportingReportIds: List<String>.from(json['supporting_report_ids'] ?? const []),
      publishedAt: DateTime.parse(json['published_at'] as String),
    );
  }
}

class XAccountSession {
  const XAccountSession({
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
    required this.username,
    required this.userId,
    required this.scopes,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
  final String username;
  final String userId;
  final List<String> scopes;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'username': username,
        'user_id': userId,
        'scopes': scopes,
      };

  factory XAccountSession.fromJson(Map<String, dynamic> json) => XAccountSession(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String?,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        username: json['username'] as String,
        userId: json['user_id'] as String,
        scopes: List<String>.from(json['scopes'] ?? const []),
      );
}
