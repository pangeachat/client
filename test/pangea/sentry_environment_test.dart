import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';

/// Covers #8505: [Environment.sentryEnvironment] must positively identify
/// staging/production from the homeserver a build actually talks to, and
/// must return null (no Sentry report) for anything else — including a
/// build with no ENVIRONMENT key at all, which is exactly what the
/// production `.env` secret ships.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Environment.appConfigOverride constructs a GetStorage('env_override')
    // box, which needs path_provider. Stub the platform channel to a temp
    // dir so the box initializes silently (its read then returns null and
    // homeServer falls back to dotenv/SYNAPSE_URL).
    final tempDir = await Directory.systemTemp.createTemp(
      'sentry_environment_test',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  test('production homeserver reports production', () {
    dotenv.testLoad(mergeWith: {'SYNAPSE_URL': 'matrix.pangea.chat'});
    expect(Environment.sentryEnvironment, 'production');
  });

  test('staging homeserver reports staging', () {
    dotenv.testLoad(mergeWith: {'SYNAPSE_URL': 'matrix.staging.pangea.chat'});
    expect(Environment.sentryEnvironment, 'staging');
  });

  test('local homeserver does not report', () {
    dotenv.testLoad(mergeWith: {'SYNAPSE_URL': 'matrix.local.pangea.chat'});
    expect(Environment.sentryEnvironment, isNull);
  });

  test('missing SYNAPSE_URL does not report', () {
    dotenv.testLoad(mergeWith: {});
    expect(Environment.sentryEnvironment, isNull);
  });

  test('ENVIRONMENT key absent (the real production .env) still reports '
      'production from the homeserver', () {
    // The checked-in .env.prod template never sets ENVIRONMENT at all — this
    // is the exact shape of the bug: isStagingEnvironment can't distinguish
    // "unset" from "misconfigured", but sentryEnvironment doesn't ask it to.
    dotenv.testLoad(mergeWith: {'SYNAPSE_URL': 'matrix.pangea.chat'});
    expect(Environment.isStagingEnvironment, isFalse);
    expect(Environment.sentryEnvironment, 'production');
  });

  test('SYNAPSE_URL carrying an explicit scheme still resolves', () {
    dotenv.testLoad(
      mergeWith: {'SYNAPSE_URL': 'https://matrix.staging.pangea.chat'},
    );
    expect(Environment.sentryEnvironment, 'staging');
  });

  test('SYNAPSE_URL with no matrix. prefix still resolves', () {
    dotenv.testLoad(mergeWith: {'SYNAPSE_URL': 'pangea.chat'});
    expect(Environment.sentryEnvironment, 'production');
  });

  test('a divergent HOME_SERVER does not change the verdict either way', () {
    // HOME_SERVER is an independent override dev_login.dart already treats
    // as untrustworthy for env decisions (its devLoginHost() doc comment:
    // "a prod SYNAPSE_URL paired with a non-prod HOME_SERVER would slip
    // through"). sentryEnvironment must read SYNAPSE_URL only.
    dotenv.testLoad(
      mergeWith: {
        'SYNAPSE_URL': 'matrix.pangea.chat',
        'HOME_SERVER': 'https://matrix.local.pangea.chat',
      },
    );
    expect(Environment.sentryEnvironment, 'production');

    dotenv.testLoad(
      mergeWith: {
        'SYNAPSE_URL': 'matrix.local.pangea.chat',
        'HOME_SERVER': 'pangea.chat',
      },
    );
    expect(Environment.sentryEnvironment, isNull);
  });

  test('a malformed SYNAPSE_URL does not throw', () {
    dotenv.testLoad(mergeWith: {'SYNAPSE_URL': 'not a valid url ::'});
    expect(() => Environment.sentryEnvironment, returnsNormally);
    expect(Environment.sentryEnvironment, isNull);
  });
}
