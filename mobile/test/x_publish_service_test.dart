import 'dart:convert';
import 'package:cinepulse_india/data/services/secure_token_storage.dart';
import 'package:cinepulse_india/data/services/x_oauth_service.dart';
import 'package:cinepulse_india/data/services/x_publish_service.dart';
import 'package:cinepulse_india/domain/models/post_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _InMemoryTokenStorage implements SecureTokenStorage {
  XAccountSession? session;

  @override
  Future<void> clearXSession() async => session = null;

  @override
  Future<XAccountSession?> loadXSession() async => session;

  @override
  Future<void> saveXSession(XAccountSession s) async => session = s;
}

void main() {
  late _InMemoryTokenStorage storage;

  setUp(() {
    storage = _InMemoryTokenStorage()
      ..session = XAccountSession(
        accessToken: 'valid-token',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        username: 'CinePulseIN',
        userId: '42',
        scopes: const ['tweet.write', 'users.read', 'offline.access'],
      );
  });

  test('requires explicit user confirmation', () async {
    final client = MockClient((_) async => http.Response('{}', 201));
    final oauth = XOAuthService(tokenStorage: storage, httpClient: client);
    final svc = XPublishService(
      tokenStorage: storage,
      oauthService: oauth,
      httpClient: client,
    );

    final res = await svc.publishPost(text: 'Valid post', userConfirmed: false);
    expect(res.isSuccess, isFalse);
    expect(res.status, PublishOutcomeStatus.invalidContent);
  });

  test('publishes and returns X post ID on HTTP 201', () async {
    final client = MockClient((req) async {
      expect(req.url.toString(), 'https://api.x.com/2/tweets');
      return http.Response(
        jsonEncode({'data': {'id': '1861452901847261184'}}),
        201,
      );
    });
    final oauth = XOAuthService(tokenStorage: storage, httpClient: client);
    final svc = XPublishService(
      tokenStorage: storage,
      oauthService: oauth,
      httpClient: client,
    );

    final res = await svc.publishPost(
      text: 'Empuraan Day 1 India Net: ₹27.50 Cr',
      userConfirmed: true,
    );
    expect(res.isSuccess, isTrue);
    expect(res.xPostId, '1861452901847261184');
    expect(res.xUrl, 'https://x.com/CinePulseIN/status/1861452901847261184');
  });

  test('handles rate limit 429 and unknown 500 + reconciles timeline', () async {
    final rateClient = MockClient((_) async => http.Response('rate limit', 429));
    final svcRate = XPublishService(
      tokenStorage: storage,
      oauthService: XOAuthService(tokenStorage: storage, httpClient: rateClient),
      httpClient: rateClient,
    );
    final rateRes = await svcRate.publishPost(text: 'Hello', userConfirmed: true);
    expect(rateRes.status, PublishOutcomeStatus.rateLimited);

    final reconcileClient = MockClient((req) async {
      if (req.method == 'POST') {
        return http.Response('upstream timeout', 503);
      }
      return http.Response(
        jsonEncode({
          'data': [
            {'id': '998877', 'text': 'Hello'}
          ]
        }),
        200,
      );
    });
    final svcReconcile = XPublishService(
      tokenStorage: storage,
      oauthService: XOAuthService(tokenStorage: storage, httpClient: reconcileClient),
      httpClient: reconcileClient,
    );
    final firstTry = await svcReconcile.publishPost(text: 'Hello', userConfirmed: true);
    expect(firstTry.status, PublishOutcomeStatus.unknownOutcome);

    final reconciled = await svcReconcile.reconcileUnknownOutcome(expectedText: 'Hello');
    expect(reconciled, isNotNull);
    expect(reconciled!.isSuccess, isTrue);
    expect(reconciled.alreadyExistedOnReconcile, isTrue);
    expect(reconciled.xPostId, '998877');
  });
}
