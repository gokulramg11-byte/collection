import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../domain/models/post_models.dart';

/// Android Keystore-backed secure storage for X OAuth 2.0 tokens ONLY.
///
/// X tokens are NEVER stored in Supabase or GitHub Actions.
abstract class SecureTokenStorage {
  Future<void> saveXSession(XAccountSession session);
  Future<XAccountSession?> loadXSession();
  Future<void> clearXSession();
}

class AndroidKeystoreTokenStorage implements SecureTokenStorage {
  AndroidKeystoreTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _xSessionKey = 'cinepulse_x_oauth_session_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<void> saveXSession(XAccountSession session) async {
    await _storage.write(
      key: _xSessionKey,
      value: jsonEncode(session.toJson()),
    );
  }

  @override
  Future<XAccountSession?> loadXSession() async {
    final raw = await _storage.read(key: _xSessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return XAccountSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clearXSession() async {
    await _storage.delete(key: _xSessionKey);
  }
}
