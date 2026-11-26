/// Runtime configuration injected via `--dart-define`.
///
/// SECURITY: Only the Supabase anon/publishable key and public X OAuth client ID
/// may be present here. Never embed Supabase service_role keys or X client secrets.
class AppConfig {
  const AppConfig._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const String xClientId = String.fromEnvironment(
    'X_CLIENT_ID',
    defaultValue: '',
  );

  static const String xRedirectUri = String.fromEnvironment(
    'X_REDIRECT_URI',
    defaultValue: 'cinepulse://oauth/x',
  );

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get isXConfigured => xClientId.isNotEmpty;
}
