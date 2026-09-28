import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_redirects.dart';

/// Supabaseの接続情報をソースコードに残さず、ビルド時に受け取ります。
class SupabaseConfig {
  SupabaseConfig._();

  static const projectUrl = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const legacyAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const authRedirectUrl = AuthRedirects.setkeep;

  static bool initialized = false;
  static LocalStorage? authStorage;
  static Object? initializationError;

  static String get key =>
      publishableKey.isNotEmpty ? publishableKey : legacyAnonKey;

  static bool get isConfigured => projectUrl.isNotEmpty && key.isNotEmpty;

  /// Checks build-time values without including them in error messages.
  /// The server still validates whether the key belongs to the project.
  static void validate({required String url, required String apiKey}) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('SUPABASE_URLの設定を確認してください');
    }
    final publishable = RegExp(r'^sb_publishable_[A-Za-z0-9_-]+$');
    final legacyJwt = RegExp(
      r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$',
    );
    if (!publishable.hasMatch(apiKey) && !legacyJwt.hasMatch(apiKey)) {
      throw const FormatException('Supabaseの公開キーの設定を確認してください');
    }
  }

  static Future<void> initialize() async {
    if (initialized) return;
    initializationError = null;
    if (!isConfigured) return;

    try {
      validate(url: projectUrl, apiKey: key);
      // Preserve the SDK's existing session key; retain access for verified erasure.
      authStorage = SharedPreferencesLocalStorage(
        persistSessionKey:
            'sb-${Uri.parse(projectUrl).host.split('.').first}-auth-token',
      );
      await Supabase.initialize(
        url: projectUrl,
        publishableKey: key,
        authOptions: FlutterAuthClientOptions(localStorage: authStorage),
      );
      initialized = true;
    } catch (error) {
      initializationError = error;
    }
  }
}
