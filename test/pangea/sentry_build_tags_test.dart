import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/constants/local.key.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'sentry_capture_harness.dart';

/// Covers #8544: a Sentry event must say WHICH BUILD produced it.
///
/// The SDK's default release is `<package>@<pubspec version>+<build number>`,
/// and pubspec's `+N` is hand-bumped, so every locally-built app reports one
/// byte-identical release string for months — `fluffychat@5.0.1+6` carried 996
/// production-tagged events over eight days with nothing separating it from a
/// deployed build. Triage could not tell whether a build predated a given fix,
/// or whether a persisted `appConfigOverride` was aiming it at production.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Environment.appConfigOverride reads a GetStorage('env_override') box that
    // needs path_provider; stub the channel to a temp dir so init is silent.
    final tempDir = await Directory.systemTemp.createTemp(
      'sentry_build_tags_test',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  setUp(() async {
    dotenv.testLoad(mergeWith: <String, String>{});
    await Environment.appConfigurationStorage.remove(
      PLocalKey.appConfigOverride,
    );
  });

  group('build channel', () {
    test('a build with no commit SHA is local', () {
      expect(Environment.sentryBuildTagsFor('')['build_channel'], 'local');
    });

    test('a build carrying a commit SHA is ci', () {
      expect(Environment.sentryBuildTagsFor('a31b92a5')['build_channel'], 'ci');
    });

    test('the running test process is itself a local build', () {
      // Nothing passes --dart-define=BUILD_COMMIT_SHA to `flutter test`, so
      // this pins that the live getter reads the same signal the pure form
      // does rather than defaulting the other way.
      expect(Environment.buildCommitSha, isEmpty);
      expect(Environment.sentryBuildTags['build_channel'], 'local');
    });
  });

  group('build commit', () {
    test('is the SHA on a ci build', () {
      expect(
        Environment.sentryBuildTagsFor('a31b92a5')['build_commit'],
        'a31b92a5',
      );
    });

    test('is absent — not empty — on a local build', () {
      // An empty-string tag is a value Sentry indexes and filters on, so it
      // would read as "this build has a commit, and it is nothing".
      expect(
        Environment.sentryBuildTagsFor(''),
        isNot(contains('build_commit')),
      );
    });
  });

  group('config override', () {
    test('false when no override is persisted', () {
      expect(Environment.sentryBuildTags['config_override'], 'false');
    });

    test('true when an override is persisted', () async {
      // The hypothesis this tag exists to kill: an override outranks dotenv
      // and survives a pull and a rebuild, so a build aimed at the production
      // homeserver by a stale override is indistinguishable from one whose
      // .env says production.
      await Environment.appConfigurationStorage.write(
        PLocalKey.appConfigOverride,
        const AppConfigOverride(synapseURL: 'matrix.pangea.chat').toJson(),
      );
      expect(Environment.sentryBuildTags['config_override'], 'true');
    });

    test('the override that flips it also drives sentryEnvironment', () async {
      // Both read the same override, which is what makes the pairing
      // diagnostic: environment=production + config_override=true is a
      // redirected local build, not a production one.
      dotenv.testLoad(
        mergeWith: <String, String>{'SYNAPSE_URL': 'matrix.local.pangea.chat'},
      );
      expect(Environment.sentryEnvironment, isNull);

      await Environment.appConfigurationStorage.write(
        PLocalKey.appConfigOverride,
        const AppConfigOverride(synapseURL: 'matrix.pangea.chat').toJson(),
      );
      expect(Environment.sentryEnvironment, 'production');
      expect(Environment.sentryBuildTags['config_override'], 'true');
    });
  });

  group('the tags reach the event', () {
    final harness = SentryCaptureHarness();

    setUp(() async {
      ErrorHandler.resetReportedOnceKeysForTest();
      await harness.init();
      await ErrorHandler.applyBuildTags();
    });

    tearDown(() => harness.close());

    test('a reported error carries the build tags', () async {
      // Asserted on the event Sentry would send, not on the map in isolation:
      // logError captures `withScope`, and a scope that did not inherit the
      // global tags would drop them silently.
      final event = await harness.capture(
        () => ErrorHandler.logError(e: Exception('boom'), data: {}),
      );
      expect(event.tags?['build_channel'], 'local');
      expect(event.tags?['config_override'], 'false');
    });
  });
}
