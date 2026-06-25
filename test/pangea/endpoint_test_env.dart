import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Single source of truth for the target URLs every endpoint test points at.
///
/// All endpoint tests (choreo / synapse / cms) resolve their base URLs through
/// this helper, so they always hit the SAME environment — whatever `client/.env`
/// says. Keep the three URLs in `.env` pointed at one environment (all local, or
/// all staging); there is no single base URL because locally the services run on
/// different ports (Synapse :8008, choreo :8002, CMS :13134) while staging/prod
/// share `api.staging.pangea.chat`.
///
/// This mirrors the dotenv layer of `Environment` but deliberately skips
/// `Environment`'s runtime `appConfigOverride` (GetStorage-backed, not
/// initialised in `flutter test`).
class EndpointTestEnv {
  static bool _loaded = false;

  /// Whether `client/.env` exists. The endpoint suites are local-only (they hit
  /// a live Synapse/choreo/CMS), so on CI — where there is no `.env` — each
  /// suite skips itself instead of crashing in `setUpAll`. See
  /// `testing.instructions.md`.
  static bool get available => File('.env').existsSync();

  static void load() {
    if (_loaded) return;
    dotenv.testLoad(fileInput: File('.env').readAsStringSync());
    _loaded = true;
  }

  static String _require(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw StateError('$key is not set in client/.env');
    }
    return value;
  }

  /// Matrix homeserver base, e.g. http://localhost:8008.
  static String get synapseUrl => _require('SYNAPSE_URL');

  /// Choreographer host base with any trailing `/choreo` stripped (callers add
  /// the `/choreo` path), mirroring `Environment.choreoApi`.
  static String get choreoApi =>
      _require('CHOREO_API').replaceAll(RegExp(r'/choreo/?$'), '');

  /// CMS host base, mirroring `Environment.cmsApi`: `CMS_API`, else `CHOREO_API`
  /// (works for staging/prod's shared domain; set `CMS_API` explicitly locally).
  static String get cmsApi => dotenv.env['CMS_API'] ?? choreoApi;


  static String? get testUsername => dotenv.env['TEST_MATRIX_USERNAME'];
  static String? get testPassword => dotenv.env['TEST_MATRIX_PASSWORD'];

  /// A course-plan-activity id that exists in the target CMS, for endpoints that
  /// fetch an activity (e.g. activity_plan/feedback). Environment-specific — set
  /// it to a real id in the environment `.env` points at. Null → those tests skip.
  static String? get testActivityId => dotenv.env['TEST_ACTIVITY_ID'];
}
