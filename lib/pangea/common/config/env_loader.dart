import 'package:flutter/foundation.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Loads environment config from the single root `.env`.
///
/// On web the root `.env` is not part of the asset bundle; it is served at
/// the web root (`/.env`) — by the Flutter dev server in local dev and by
/// the deploy pipeline, which writes `build/web/.env`. On native platforms
/// the root `.env` is a bundled asset (pubspec lines uncommented by
/// `scripts/enable_mobile_env.patch` in CI).
class EnvLoader {
  /// Distinguishes real env content from an SPA index-fallback response:
  /// servers that rewrite unknown paths to index.html return 200 with HTML,
  /// which must not be fed to dotenv.
  @visibleForTesting
  static bool looksLikeEnvFile(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty || trimmed.startsWith('<')) return false;
    final assignment = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*\s*=', multiLine: true);
    return assignment.hasMatch(trimmed);
  }

  @visibleForTesting
  static Future<bool> tryLoadFromWebRoot({http.Client? client}) async {
    final httpClient = client ?? http.Client();
    try {
      // Root-absolute: with path URLs the app can boot on any nested path
      // (`/home/login`), and a RELATIVE resolve fetched `/home/.env` — which
      // the SPA fallback answers with index.html, silently failing the load.
      final response = await httpClient.get(Uri.base.resolve('/.env'));
      if (response.statusCode != 200 || !looksLikeEnvFile(response.body)) {
        return false;
      }
      dotenv.testLoad(fileInput: response.body);
      return true;
    } catch (_) {
      return false;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  static Future<void> load() async {
    if (kIsWeb && await tryLoadFromWebRoot()) return;
    // Native asset load; also the web fallback for older deployed artifacts
    // that still bundle assets/.env.
    await dotenv.load(fileName: '.env');
  }
}
