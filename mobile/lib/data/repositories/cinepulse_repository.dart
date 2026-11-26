import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/box_office_models.dart';
import '../../domain/models/post_models.dart';

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.latestRun,
    required this.monitoredMoviesCount,
    required this.pendingDraftsCount,
    required this.publishedTodayCount,
    required this.conflictsCount,
    required this.sources,
    required this.recentMovies,
    this.isFromCache = false,
  });

  final CollectionRun? latestRun;
  final int monitoredMoviesCount;
  final int pendingDraftsCount;
  final int publishedTodayCount;
  final int conflictsCount;
  final List<SourceHealth> sources;
  final List<Movie> recentMovies;
  final bool isFromCache;
}

abstract class CinePulseRepository {
  Future<DashboardSnapshot> fetchDashboard();
  Future<List<PostDraft>> fetchActiveDrafts();
  Future<List<PublishedPost>> fetchPublishedHistory();
  Future<List<Movie>> fetchMovies();
  Future<List<ReconciledCollection>> fetchMovieCollections(String movieId);
  Future<List<CollectionReport>> fetchMovieReports(String movieId);
  Future<void> saveDraftEdit({
    required String draftId,
    required String editedText,
    required List<String> hashtags,
    required int weightedCharCount,
    required bool isValidLength,
    required bool numericalEditConfirmed,
    Map<String, dynamic>? numericalAudit,
  });
  Future<void> resetDraftToOriginal(String draftId);
  Future<void> cancelDraft(String draftId);
  Future<void> markDraftPublishing(String draftId);
  Future<void> markDraftFailed(String draftId, String errorMessage);
  Future<void> markDraftPublished({
    required PostDraft draft,
    required String userId,
    required String finalText,
    required String xPostId,
    required String xUrl,
  });
}

class SupabaseCinePulseRepository implements CinePulseRepository {
  SupabaseCinePulseRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const _cacheKeyDashboard = 'cinepulse_cached_dashboard_v1';

  @override
  Future<DashboardSnapshot> fetchDashboard() async {
    try {
      final runsRes = await _client
          .from('collection_runs')
          .select()
          .order('started_at', ascending: false)
          .limit(1);
      final sourcesRes = await _client.from('sources').select().order('priority');
      final moviesRes = await _client
          .from('movies')
          .select()
          .eq('is_monitored', true)
          .order('release_date', ascending: false)
          .limit(50);
      final draftsRes = await _client
          .from('post_drafts')
          .select('id,status')
          .inFilter('status', ['PENDING_REVIEW', 'EDITED', 'FAILED']);
      final conflictsRes = await _client
          .from('reconciled_collections')
          .select('id')
          .eq('has_conflict', true);

      final todayStartUtc = DateTime.now().toUtc();
      final dayFloor = DateTime.utc(todayStartUtc.year, todayStartUtc.month, todayStartUtc.day);
      final publishedRes = await _client
          .from('published_posts')
          .select('id')
          .gte('published_at', dayFloor.toIso8601String());

      final runs = (runsRes as List).map((e) => CollectionRun.fromJson(e)).toList();
      final sources = (sourcesRes as List).map((e) => SourceHealth.fromJson(e)).toList();
      final movies = (moviesRes as List).map((e) => Movie.fromJson(e)).toList();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKeyDashboard,
        jsonEncode({
          'monitored': movies.length,
          'pending': (draftsRes as List).length,
          'published_today': (publishedRes as List).length,
          'conflicts': (conflictsRes as List).length,
        }),
      );

      return DashboardSnapshot(
        latestRun: runs.isNotEmpty ? runs.first : null,
        monitoredMoviesCount: movies.length,
        pendingDraftsCount: draftsRes.length,
        publishedTodayCount: publishedRes.length,
        conflictsCount: conflictsRes.length,
        sources: sources,
        recentMovies: movies.take(5).toList(),
      );
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKeyDashboard);
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return DashboardSnapshot(
          latestRun: null,
          monitoredMoviesCount: map['monitored'] as int? ?? 0,
          pendingDraftsCount: map['pending'] as int? ?? 0,
          publishedTodayCount: map['published_today'] as int? ?? 0,
          conflictsCount: map['conflicts'] as int? ?? 0,
          sources: const [],
          recentMovies: const [],
          isFromCache: true,
        );
      }
      rethrow;
    }
  }

  @override
  Future<List<PostDraft>> fetchActiveDrafts() async {
    final rows = await _client
        .from('post_drafts')
        .select()
        .inFilter('status', ['PENDING_REVIEW', 'EDITED', 'FAILED', 'PUBLISHING'])
        .order('created_at', ascending: false);
    return (rows as List).map((e) => PostDraft.fromJson(e)).toList();
  }

  @override
  Future<List<PublishedPost>> fetchPublishedHistory() async {
    final rows = await _client
        .from('published_posts')
        .select()
        .order('published_at', ascending: false)
        .limit(100);
    return (rows as List).map((e) => PublishedPost.fromJson(e)).toList();
  }

  @override
  Future<List<Movie>> fetchMovies() async {
    final rows = await _client
        .from('movies')
        .select()
        .order('release_date', ascending: false)
        .limit(200);
    return (rows as List).map((e) => Movie.fromJson(e)).toList();
  }

  @override
  Future<List<ReconciledCollection>> fetchMovieCollections(String movieId) async {
    final rows = await _client
        .from('reconciled_collections')
        .select()
        .eq('movie_id', movieId)
        .order('reporting_date', ascending: false);
    return (rows as List).map((e) => ReconciledCollection.fromJson(e)).toList();
  }

  @override
  Future<List<CollectionReport>> fetchMovieReports(String movieId) async {
    final rows = await _client
        .from('collection_reports')
        .select('*, sources(name)')
        .eq('movie_id', movieId)
        .order('reporting_date', ascending: false);
    return (rows as List).map((e) => CollectionReport.fromJson(e)).toList();
  }

  @override
  Future<void> saveDraftEdit({
    required String draftId,
    required String editedText,
    required List<String> hashtags,
    required int weightedCharCount,
    required bool isValidLength,
    required bool numericalEditConfirmed,
    Map<String, dynamic>? numericalAudit,
  }) async {
    await _client.from('post_drafts').update({
      'edited_text': editedText,
      'hashtags': hashtags,
      'weighted_char_count': weightedCharCount,
      'is_valid_length': isValidLength,
      'status': DraftStatus.edited.apiValue,
      'numerical_edit_confirmed': numericalEditConfirmed,
      if (numericalAudit != null) 'numerical_edit_audit': numericalAudit,
    }).eq('id', draftId);
  }

  @override
  Future<void> resetDraftToOriginal(String draftId) async {
    await _client.from('post_drafts').update({
      'edited_text': null,
      'status': DraftStatus.pendingReview.apiValue,
      'numerical_edit_confirmed': false,
    }).eq('id', draftId);
  }

  @override
  Future<void> cancelDraft(String draftId) async {
    await _client.from('post_drafts').update({
      'status': DraftStatus.cancelled.apiValue,
    }).eq('id', draftId);
  }

  @override
  Future<void> markDraftPublishing(String draftId) async {
    await _client.from('post_drafts').update({
      'status': DraftStatus.publishing.apiValue,
      'last_error': null,
    }).eq('id', draftId);
  }

  @override
  Future<void> markDraftFailed(String draftId, String errorMessage) async {
    await _client.from('post_drafts').update({
      'status': DraftStatus.failed.apiValue,
      'last_error': errorMessage,
    }).eq('id', draftId);
  }

  @override
  Future<void> markDraftPublished({
    required PostDraft draft,
    required String userId,
    required String finalText,
    required String xPostId,
    required String xUrl,
  }) async {
    await _client.from('post_drafts').update({
      'edited_text': finalText,
      'status': DraftStatus.published.apiValue,
      'last_error': null,
    }).eq('id', draft.id);

    await _client.from('published_posts').insert({
      'draft_id': draft.id,
      'user_id': userId,
      'final_text': finalText,
      'x_post_id': xPostId,
      'x_url': xUrl,
      'category': draft.category.apiValue,
      'supporting_report_ids': const <String>[],
      'published_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
