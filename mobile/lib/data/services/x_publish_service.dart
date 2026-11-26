import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../core/utils/x_character_counter.dart';
import '../../domain/models/post_models.dart';
import 'secure_token_storage.dart';
import 'x_oauth_service.dart';

enum PublishOutcomeStatus {
  published,
  authExpired,
  rateLimited,
  invalidContent,
  networkError,
  unknownOutcome,
  apiError,
}

class XPublishResult {
  const XPublishResult({
    required this.status,
    this.xPostId,
    this.xUrl,
    this.errorMessage,
    this.alreadyExistedOnReconcile = false,
  });

  final PublishOutcomeStatus status;
  final String? xPostId;
  final String? xUrl;
  final String? errorMessage;
  final bool alreadyExistedOnReconcile;

  bool get isSuccess => status == PublishOutcomeStatus.published;
}

/// Official X API v2 manual post publisher with duplicate-prevention reconciliation.
class XPublishService {
  XPublishService({
    required SecureTokenStorage tokenStorage,
    required XOAuthService oauthService,
    http.Client? httpClient,
    Duration requestTimeout = const Duration(seconds: 20),
  })  : _tokenStorage = tokenStorage,
        _oauthService = oauthService,
        _http = httpClient ?? http.Client(),
        _timeout = requestTimeout;

  static const _tweetsEndpoint = 'https://api.x.com/2/tweets';

  final SecureTokenStorage _tokenStorage;
  final XOAuthService _oauthService;
  final http.Client _http;
  final Duration _timeout;

  /// Publishes [text] ONLY when called after explicit user confirmation.
  Future<XPublishResult> publishPost({
    required String text,
    required bool userConfirmed,
  }) async {
    if (!userConfirmed) {
      return const XPublishResult(
        status: PublishOutcomeStatus.invalidContent,
        errorMessage: 'Explicit user confirmation is required before publishing.',
      );
    }

    final validation = XCharacterCounter.validate(text);
    if (!validation.isValid) {
      return XPublishResult(
        status: PublishOutcomeStatus.invalidContent,
        errorMessage: validation.suggestions.join(' '),
      );
    }

    var session = await _tokenStorage.loadXSession();
    if (session == null) {
      return const XPublishResult(
        status: PublishOutcomeStatus.authExpired,
        errorMessage: 'No connected X account. Connect your X account in Settings.',
      );
    }

    session = await _oauthService.refreshSessionIfNeeded(session);
    if (session == null) {
      return const XPublishResult(
        status: PublishOutcomeStatus.authExpired,
        errorMessage: 'X session expired. Please reconnect your X account.',
      );
    }

    try {
      final resp = await _http
          .post(
            Uri.parse(_tweetsEndpoint),
            headers: {
              'Authorization': 'Bearer ${session.accessToken}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'text': text.trim()}),
          )
          .timeout(_timeout);

      if (resp.statusCode == 201 || resp.statusCode == 200) {
        final data = (jsonDecode(resp.body) as Map<String, dynamic>)['data']
            as Map<String, dynamic>?;
        final postId = data?['id'] as String?;
        if (postId == null || postId.isEmpty) {
          return const XPublishResult(
            status: PublishOutcomeStatus.unknownOutcome,
            errorMessage:
                'X API returned success without a post ID. Reconcile before retrying.',
          );
        }
        return XPublishResult(
          status: PublishOutcomeStatus.published,
          xPostId: postId,
          xUrl: 'https://x.com/${session.username}/status/$postId',
        );
      }

      if (resp.statusCode == 401) {
        return const XPublishResult(
          status: PublishOutcomeStatus.authExpired,
          errorMessage: 'X authentication expired or revoked (HTTP 401).',
        );
      }

      if (resp.statusCode == 429) {
        return const XPublishResult(
          status: PublishOutcomeStatus.rateLimited,
          errorMessage: 'X API rate limit reached (HTTP 429). Please retry later.',
        );
      }

      if (resp.statusCode == 400 || resp.statusCode == 403 || resp.statusCode == 422) {
        return XPublishResult(
          status: PublishOutcomeStatus.apiError,
          errorMessage: 'X API rejected post (${resp.statusCode}): ${resp.body}',
        );
      }

      // 5xx or ambiguous status -> unknown outcome
      return XPublishResult(
        status: PublishOutcomeStatus.unknownOutcome,
        errorMessage:
            'Ambiguous X API response (${resp.statusCode}). Reconcile on X before retrying.',
      );
    } on TimeoutException {
      return const XPublishResult(
        status: PublishOutcomeStatus.unknownOutcome,
        errorMessage:
            'Request timed out. The post may have been created on X—reconcile before retrying.',
      );
    } on SocketException catch (e) {
      return XPublishResult(
        status: PublishOutcomeStatus.networkError,
        errorMessage: 'Network error: ${e.message}',
      );
    } catch (e) {
      return XPublishResult(
        status: PublishOutcomeStatus.unknownOutcome,
        errorMessage: 'Unexpected publishing error: $e',
      );
    }
  }

  /// Checks recent tweets of the connected user to prevent duplicate posts
  /// when a prior publish request had an unknown outcome.
  Future<XPublishResult?> reconcileUnknownOutcome({required String expectedText}) async {
    final session = await _tokenStorage.loadXSession();
    if (session == null) return null;

    final refreshed = await _oauthService.refreshSessionIfNeeded(session);
    if (refreshed == null) return null;

    final uri = Uri.parse('https://api.x.com/2/users/${refreshed.userId}/tweets')
        .replace(queryParameters: {'max_results': '5'});

    final resp = await _http
        .get(uri, headers: {'Authorization': 'Bearer ${refreshed.accessToken}'})
        .timeout(_timeout);

    if (resp.statusCode != 200) return null;
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final tweets = (body['data'] as List<dynamic>? ?? const []);
    final normalizedExpected = expectedText.trim();

    for (final item in tweets) {
      final map = item as Map<String, dynamic>;
      final tweetText = (map['text'] as String? ?? '').trim();
      if (tweetText == normalizedExpected) {
        final id = map['id'] as String;
        return XPublishResult(
          status: PublishOutcomeStatus.published,
          xPostId: id,
          xUrl: 'https://x.com/${refreshed.username}/status/$id',
          alreadyExistedOnReconcile: true,
        );
      }
    }
    return null;
  }
}
