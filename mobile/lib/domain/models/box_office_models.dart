enum CollectionMetric {
  indiaNet('INDIA_NET', 'India Net'),
  indiaGross('INDIA_GROSS', 'India Gross'),
  overseasGross('OVERSEAS_GROSS', 'Overseas Gross'),
  worldwideGross('WORLDWIDE_GROSS', 'Worldwide Gross');

  const CollectionMetric(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static CollectionMetric fromApi(String value) {
    return CollectionMetric.values.firstWhere(
      (e) => e.apiValue == value,
      orElse: () => CollectionMetric.indiaNet,
    );
  }
}

enum ReportingPeriodType {
  daily('DAILY', 'Daily'),
  cumulative('CUMULATIVE', 'Cumulative');

  const ReportingPeriodType(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static ReportingPeriodType fromApi(String value) {
    return ReportingPeriodType.values.firstWhere(
      (e) => e.apiValue == value,
      orElse: () => ReportingPeriodType.daily,
    );
  }
}

enum ReportSourceStatus {
  estimate('ESTIMATE', 'Estimate'),
  updatedEstimate('UPDATED_ESTIMATE', 'Updated Estimate'),
  tradeReported('TRADE_REPORTED', 'Trade Reported'),
  producerReported('PRODUCER_REPORTED', 'Producer Reported'),
  reportedFinal('REPORTED_FINAL', 'Reported Final'),
  audited('AUDITED', 'Audited');

  const ReportSourceStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static ReportSourceStatus fromApi(String value) {
    return ReportSourceStatus.values.firstWhere(
      (e) => e.apiValue == value,
      orElse: () => ReportSourceStatus.estimate,
    );
  }
}

class Movie {
  const Movie({
    required this.id,
    this.tmdbId,
    required this.title,
    this.originalTitle,
    required this.primaryLanguage,
    required this.languages,
    this.releaseDate,
    this.posterPath,
    this.overview,
    this.isMonitored = true,
    this.latestIndiaNet,
    this.latestIndiaGross,
    this.latestOverseasGross,
    this.latestWorldwideGross,
    this.latestReportDate,
  });

  final String id;
  final int? tmdbId;
  final String title;
  final String? originalTitle;
  final String primaryLanguage;
  final List<String> languages;
  final DateTime? releaseDate;
  final String? posterPath;
  final String? overview;
  final bool isMonitored;
  final double? latestIndiaNet;
  final double? latestIndiaGross;
  final double? latestOverseasGross;
  final double? latestWorldwideGross;
  final DateTime? latestReportDate;

  factory Movie.fromJson(Map<String, dynamic> json) {
    return Movie(
      id: json['id'] as String,
      tmdbId: json['tmdb_id'] as int?,
      title: json['title'] as String,
      originalTitle: json['original_title'] as String?,
      primaryLanguage: json['primary_language'] as String? ?? 'Other',
      languages: List<String>.from(json['languages'] ?? const []),
      releaseDate: json['release_date'] != null
          ? DateTime.tryParse(json['release_date'] as String)
          : null,
      posterPath: json['poster_path'] as String?,
      overview: json['overview'] as String?,
      isMonitored: json['is_monitored'] as bool? ?? true,
    );
  }
}

class CollectionReport {
  const CollectionReport({
    required this.id,
    required this.movieId,
    required this.sourceId,
    required this.sourceName,
    required this.metric,
    required this.periodType,
    this.dayNumber,
    required this.reportingDate,
    required this.amountInrCrores,
    required this.currency,
    required this.sourceStatus,
    required this.sourceUrl,
    this.originalReportRef,
    this.publishedAt,
    required this.retrievedAt,
    this.revisionNumber = 1,
  });

  final String id;
  final String movieId;
  final String sourceId;
  final String sourceName;
  final CollectionMetric metric;
  final ReportingPeriodType periodType;
  final int? dayNumber;
  final DateTime reportingDate;
  final double amountInrCrores;
  final String currency;
  final ReportSourceStatus sourceStatus;
  final String sourceUrl;
  final String? originalReportRef;
  final DateTime? publishedAt;
  final DateTime retrievedAt;
  final int revisionNumber;

  factory CollectionReport.fromJson(Map<String, dynamic> json) {
    final sourceObj = json['sources'] as Map<String, dynamic>?;
    return CollectionReport(
      id: json['id'] as String,
      movieId: json['movie_id'] as String,
      sourceId: json['source_id'] as String,
      sourceName: sourceObj?['name'] as String? ?? 'Verified Source',
      metric: CollectionMetric.fromApi(json['metric'] as String),
      periodType: ReportingPeriodType.fromApi(json['period_type'] as String),
      dayNumber: json['day_number'] as int?,
      reportingDate: DateTime.parse(json['reporting_date'] as String),
      amountInrCrores: double.parse(json['amount_inr_crores'].toString()),
      currency: json['currency'] as String? ?? 'INR',
      sourceStatus: ReportSourceStatus.fromApi(json['source_status'] as String),
      sourceUrl: json['source_url'] as String,
      originalReportRef: json['original_report_ref'] as String?,
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'] as String)
          : null,
      retrievedAt: DateTime.parse(json['retrieved_at'] as String),
      revisionNumber: json['revision_number'] as int? ?? 1,
    );
  }
}

class ReconciledCollection {
  const ReconciledCollection({
    required this.id,
    required this.movieId,
    required this.metric,
    required this.periodType,
    this.dayNumber,
    required this.reportingDate,
    required this.amountInrCrores,
    required this.confidenceStatus,
    required this.hasConflict,
    this.conflictDetails,
    required this.supportingReportIds,
    required this.methodologyNote,
  });

  final String id;
  final String movieId;
  final CollectionMetric metric;
  final ReportingPeriodType periodType;
  final int? dayNumber;
  final DateTime reportingDate;
  final double amountInrCrores;
  final ReportSourceStatus confidenceStatus;
  final bool hasConflict;
  final Map<String, dynamic>? conflictDetails;
  final List<String> supportingReportIds;
  final String methodologyNote;

  factory ReconciledCollection.fromJson(Map<String, dynamic> json) {
    return ReconciledCollection(
      id: json['id'] as String,
      movieId: json['movie_id'] as String,
      metric: CollectionMetric.fromApi(json['metric'] as String),
      periodType: ReportingPeriodType.fromApi(json['period_type'] as String),
      dayNumber: json['day_number'] as int?,
      reportingDate: DateTime.parse(json['reporting_date'] as String),
      amountInrCrores: double.parse(json['reconciled_amount_inr_crores'].toString()),
      confidenceStatus: ReportSourceStatus.fromApi(json['confidence_status'] as String),
      hasConflict: json['has_conflict'] as bool? ?? false,
      conflictDetails: json['conflict_details'] as Map<String, dynamic>?,
      supportingReportIds: List<String>.from(json['supporting_report_ids'] ?? const []),
      methodologyNote: json['methodology_note'] as String? ?? '',
    );
  }
}

class SourceHealth {
  const SourceHealth({
    required this.id,
    required this.code,
    required this.name,
    required this.accessMethod,
    required this.healthStatus,
    this.lastSuccessAt,
    this.lastError,
  });

  final String id;
  final String code;
  final String name;
  final String accessMethod;
  final String healthStatus;
  final DateTime? lastSuccessAt;
  final String? lastError;

  factory SourceHealth.fromJson(Map<String, dynamic> json) {
    return SourceHealth(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      accessMethod: json['access_method'] as String,
      healthStatus: json['health_status'] as String,
      lastSuccessAt: json['last_success_at'] != null
          ? DateTime.tryParse(json['last_success_at'] as String)
          : null,
      lastError: json['last_error'] as String?,
    );
  }
}

class CollectionRun {
  const CollectionRun({
    required this.id,
    required this.triggerType,
    required this.status,
    required this.startedAt,
    this.completedAt,
    required this.moviesDiscovered,
    required this.reportsCollected,
    required this.conflictsDetected,
    required this.draftsGenerated,
    this.errorSummary,
  });

  final String id;
  final String triggerType;
  final String status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int moviesDiscovered;
  final int reportsCollected;
  final int conflictsDetected;
  final int draftsGenerated;
  final String? errorSummary;

  factory CollectionRun.fromJson(Map<String, dynamic> json) {
    return CollectionRun(
      id: json['id'] as String,
      triggerType: json['trigger_type'] as String,
      status: json['status'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'] as String)
          : null,
      moviesDiscovered: json['movies_discovered'] as int? ?? 0,
      reportsCollected: json['reports_collected'] as int? ?? 0,
      conflictsDetected: json['conflicts_detected'] as int? ?? 0,
      draftsGenerated: json['drafts_generated'] as int? ?? 0,
      errorSummary: json['error_summary'] as String?,
    );
  }
}
