import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/languages/language_repo.dart';

/// CMS endpoint tests — exercise the client's real CMS repos against a live
/// Payload CMS at `Environment.cmsApi` (local stack by default; set `CMS_API`
/// in `client/.env` to point elsewhere).
///
/// Like the synapse tests, CMS is an **internal** service with no paid API, so
/// the calls run for real (no `mock: true`). Integration-tier; needs a running
/// CMS, so local-only, not a PR gate — see testing.instructions.md. Confirms the
/// CMS responses still parse into the client's models.
void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: File('.env').readAsStringSync());
  });

  group('CMS endpoint tests', () {
    test('languages endpoint returns models the client can parse', () async {
      final result = await LanguageRepo.get();
      expect(
        result.isValue,
        isTrue,
        reason: result.isError ? '${result.asError!.error}' : '',
      );
      final languages = result.asValue!.value;
      expect(languages, isNotEmpty, reason: 'CMS returned no languages');
    });
  });
}
