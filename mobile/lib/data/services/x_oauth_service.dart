import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../../core/config/app_config.dart';
import '../../domain/models/post_models.dart';
import 'secure_token_storage.dart';

class PkcePair {
  const PkcePair({required this.codeVerifier, required this.codeChallenge});
  final String codeVerifier;
  final String codeChallenge;
}

/// Official X API OAuth 2.0 Authorization Code Flow with PKCE (Native Public Client).
///
/// - Never asks for or stores X passwords.
/// - Never embeds a client secret.
/// - Requests only supported scopes: tweet.write, users.read, offline.access.
class XOAuthService {
  XOAuthService({
    required SecureTokenStorage tokenStorage,
    http.Client? httpClient,
  })  : _tokenStorage = tokenStorage,
        _http = httpClient ?? http.Client();

  static const List<String> supportedScopes = [
    'tweet.write',
    'users.read',
    'offline.access',
  ];

  static const _authorizeEndpoint = 'https://x.com/i/oauth2/authorize';
  static const _tokenEndpoint = 'https://api.x.com/2/oauth2/token';
  static const _revokeEndpoint = 'https://api.x.com/2/oauth2/revoke';
  static const _meEndpoint = 'https://api.x.com/2/users/me';

  final SecureTokenStorage _tokenStorage;
  final http.Client _http;

  PkcePair generatePkcePair() {
    final rand = Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    final verifier = base64UrlEncode(bytes).replaceAll('=', '');
    final digest = sha256.convert(utf8.encode(verifier));
    final challenge = base64UrlEncode(digest.bytes).replaceAll('=', '');
    return PkcePair(codeVerifier: verifier, codeChallenge: challenge);
  }

  Uri buildAuthorizeUri({required String state, required String codeChallenge}) {
    return Uri.parse(_authorizeEndpoint).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': AppConfig.xClientId,
        'redirect_uri': AppConfig.xRedirectUri,
        'scope': supportedScopes.join(' '),
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      },
    );
  }

  Future<XAccountSession> exchangeCodeForTokens({
    required String authorizationCode,
    required String codeVerifier,
  }) async {
    final resp = await _http.post(
      Uri.parse(_tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'code': authorizationCode,
        'grant_type': 'authorization_code',
        'client_id': AppConfig.xClientId,
        'redirect_uri': AppConfig.xRedirectUri,
        'code_verifier': codeVerifier,
      },
    );

    if (resp.statusCode != 200) {
      throw Exception('X OAuth token exchange failed (${resp.statusCode}): ${resp.body}');
    }

    final tokenData = jsonDecode(resp.body) as Map<String, dynamic>;
    final accessToken = tokenData['access_token'] as String;
    final refreshToken = tokenData['refresh_token'] as String?;
    final expiresIn = tokenData['expires_in'] as int? ?? 7200;
    final scopeStr = tokenData['scope'] as String? ?? supportedScopes.join(' ');

    final meResp = await _http.get(
      Uri.parse(_meEndpoint),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (meResp.statusCode != 200) {
      throw Exception('Failed to fetch authenticated X user (${meResp.statusCode})');
    }
    final meData = (jsonDecode(meResp.body) as Map<String, dynamic>)['data']
        as Map<String, dynamic>;

    final session = XAccountSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: expiresIn - 60)),
      username: meData['username'] as String,
      userId: meData['id'] as String,
      scopes: scopeStr.split(' ').where((s) => s.isNotEmpty).toList(),
    );
    await _tokenStorage.saveXSession(session);
    return session;
  }

  Future<XAccountSession?> refreshSessionIfNeeded(XAccountSession current) async {
    if (!current.isExpired) return current;
    if (current.refreshToken == null || current.refreshToken!.isEmpty) {
      return null;
    }

    final resp = await _http.post(
      Uri.parse(_tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'refresh_token': current.refreshToken!,
        'grant_type': 'refresh_token',
        'client_id': AppConfig.xClientId,
      },
    );

    if (resp.statusCode != 200) {
      return null;
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final updated = XAccountSession(
      accessToken: data['access_token'] as String,
      refreshToken: (data['refresh_token'] as String?) ?? current.refreshToken,
      expiresAt: DateTime.now()
          .toUtc()
          .add(Duration(seconds: (data['expires_in'] as int? ?? 7200) - 60)),
      username: current.username,
      userId: current.userId,
      scopes: current.scopes,
    );
    await _tokenStorage.saveXSession(updated);
    return updated;
  }

  Future<void> disconnectAndRevoke() async {
    final current = await _tokenStorage.loadXSession();
    if (current != null) {
      try {
        await _http.post(
          Uri.parse(_revokeEndpoint),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'token': current.accessToken,
            'client_id': AppConfig.xClientId,
          },
        );
      } catch (_) {
        // Always clear local Keystore tokens even if remote revoke fails offline
      }
    }
    await _tokenStorage.clearXSession();
  }
}
