import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/env_loader.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/constants/local.key.dart';
import 'package:fluffychat/pangea/common/widgets/environment_banner.dart';
import 'package:fluffychat/routes/home/login/environment_switcher.dart';

const _stagingWebApp = 'https://app.staging.example.test';

/// Shaped like the staging web app's `/.env`: spaced, quoted values, its own
/// ENVIRONMENT, and a developer setting the switch must not take.
const _stagingEnvFile = """
ENVIRONMENT = 'staging'
CHOREO_API = 'https://api.staging.pangea.chat'
FRONTEND_URL='https://app.staging.pangea.chat'
SYNAPSE_URL = 'matrix.staging.pangea.chat'
TEACHER_BFF_API=https://admin-dash-api.staging.pangea.chat
STRIPE_MANAGEMENT_LINK=https://billing.stripe.com/p/login/test_9AQaI8d3O9lmaXe5kk
BOT_NAME=@bot:staging.pangea.chat
ANALYTICS_DUAL_WRITE_ENABLED=true
DOSAGE_SIGNALS_ENABLED=true
ENABLE_SEMANTICS=true
""";

Map<String, String> _parse(String envFile) =>
    Map.of((DotEnv()..testLoad(fileInput: envFile)).env);

final _staging = AppConfigOverride.fromEnvFile(
  Environment.staging,
  _parse(_stagingEnvFile),
);

MockClient _webApp(int status, String body) => MockClient((request) async {
  expect(request.url.toString(), '$_stagingWebApp/.env');
  return http.Response(body, status);
});

/// The hidden environment switcher (deployment.instructions.md § Environment
/// switcher): reading an environment's `.env`, the switch state, the gesture
/// and code, the download, the storage wipe, and the badge.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;

  setUpAll(() async {
    documents = await Directory.systemTemp.createTemp('environment_switcher');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => documents.path,
        );
    await GetStorage.init(Environment.appConfigurationStorageName);
  });

  setUp(() async {
    // A production build (its .env never sets ENVIRONMENT) naming staging.
    dotenv.testLoad(mergeWith: {'ENVIRONMENT_SWITCHER_URL': _stagingWebApp});
    await Environment.setAppConfigOverride(null);
  });

  group("reading an environment's .env", () {
    test('takes the values a switch covers', () {
      expect(_staging.environment, Environment.staging);
      expect(_staging.synapseURL, 'matrix.staging.pangea.chat');
      expect(_staging.choreoApi, 'https://api.staging.pangea.chat');
      expect(
        _staging.teacherBffApi,
        'https://admin-dash-api.staging.pangea.chat',
      );
      expect(_staging.botName, '@bot:staging.pangea.chat');
      expect(_staging.analyticsDualWriteEnabled, isTrue);
    });

    test("never moves push or takes the file's developer settings", () async {
      await Environment.setAppConfigOverride(_staging);
      expect(
        Environment.pushGatewayUrl,
        'https://sygnal.pangea.chat/_matrix/push/v1/notify',
      );
      expect(Environment.enableSemantics, isFalse);
    });

    test("a flag the file leaves out is off, not the build's", () async {
      dotenv.testLoad(mergeWith: {'LIVE_STREAMING_STT_ENABLED': 'true'});
      await Environment.setAppConfigOverride(_staging);
      expect(Environment.liveStreamingSttEnabled, isFalse);
    });

    test('a file missing a value the switch needs is refused', () {
      final envFile = _parse(_stagingEnvFile)..remove('BOT_NAME');
      expect(
        () => AppConfigOverride.fromEnvFile(Environment.staging, envFile),
        throwsA(
          isA<IncompleteEnvironmentException>().having(
            (e) => e.missingKeys,
            'missingKeys',
            ['BOT_NAME'],
          ),
        ),
      );
    });

    test('points Sentry at the switched environment', () async {
      await Environment.setAppConfigOverride(_staging);
      expect(Environment.sentryEnvironment, Environment.staging);
    });
  });

  group('EnvLoader.fetchFromWebApp', () {
    test("reads the web app's /.env", () async {
      final envFile = await EnvLoader.fetchFromWebApp(
        _stagingWebApp,
        client: _webApp(200, _stagingEnvFile),
      );
      expect(envFile['SYNAPSE_URL'], 'matrix.staging.pangea.chat');
    });

    test('refuses an HTML fallback or a missing file', () async {
      for (final (status, body) in [
        (200, '<!DOCTYPE html><html></html>'),
        (404, 'Not Found'),
      ]) {
        await expectLater(
          EnvLoader.fetchFromWebApp(
            _stagingWebApp,
            client: _webApp(status, body),
          ),
          throwsException,
        );
      }
    });
  });

  group('switch state', () {
    test('a production build with no switch talks to production', () {
      expect(Environment.buildEnvironment, Environment.production);
      expect(Environment.otherEnvironment, Environment.staging);
      expect(Environment.activeEnvironment, Environment.production);
      expect(Environment.isSwitched, isFalse);
    });

    test('switching a production build to staging', () async {
      await Environment.setAppConfigOverride(_staging);
      expect(Environment.activeEnvironment, Environment.staging);
      expect(Environment.isSwitched, isTrue);
      expect(Environment.synapseURL, _staging.synapseURL);
      expect(Environment.cmsApi, _staging.choreoApi);
    });

    test('a staging build switched to staging is not switched', () async {
      dotenv.testLoad(mergeWith: {'ENVIRONMENT': Environment.staging});
      await Environment.setAppConfigOverride(_staging);
      expect(Environment.isSwitched, isFalse);
    });
  });

  group('tap target', () {
    final onAndroid = TargetPlatformVariant.only(TargetPlatform.android);
    const relaunchNotice =
        'Close the app completely and open it again to finish switching.';

    Future<void> pumpLoginHeading(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Center(
              child: EnvironmentSwitcherTapTarget(child: Text('Log in')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapHeading(WidgetTester tester, int times) async {
      for (var i = 0; i < times; i++) {
        await tester.tap(find.text('Log in'));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    Future<void> enterCode(WidgetTester tester, String code) async {
      await tester.enterText(find.byType(TextField), code);
      await tester.tap(find.text('Ok'));
      await tester.pumpAndSettle();
    }

    Future<void> openPicker(WidgetTester tester) async {
      await pumpLoginHeading(tester);
      await tapHeading(tester, EnvironmentSwitcherTapTarget.tapsToOpen);
      await enterCode(tester, EnvironmentSwitcherTapTarget.teamCode);
    }

    /// Lets the download, the storage writes and the erase finish: file IO
    /// never completes in fake time.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.pumpAndSettle();
    }

    Future<void> pick(WidgetTester tester, String environment) async {
      await tester.tap(find.text(environment));
      await settle(tester);
    }

    Future<void> seedOldEnvironmentStorage(WidgetTester tester) =>
        tester.runAsync(() async {
          await GetStorage.init('class_storage');
          await GetStorage('class_storage').write('pending_code', 'abc123');
        });

    testWidgets('fewer than 7 taps do nothing', (tester) async {
      await pumpLoginHeading(tester);
      await tapHeading(tester, EnvironmentSwitcherTapTarget.tapsToOpen - 1);
      expect(find.text('Team code'), findsNothing);
    }, variant: onAndroid);

    testWidgets('a pause between taps starts the count again', (tester) async {
      await pumpLoginHeading(tester);
      await tapHeading(tester, EnvironmentSwitcherTapTarget.tapsToOpen - 1);
      await tester.runAsync(
        () => Future<void>.delayed(
          EnvironmentSwitcherTapTarget.maxGapBetweenTaps * 1.2,
        ),
      );
      await tapHeading(tester, 1);
      expect(find.text('Team code'), findsNothing);
    }, variant: onAndroid);

    testWidgets('a wrong code closes the prompt and offers nothing', (
      tester,
    ) async {
      await pumpLoginHeading(tester);
      await tapHeading(tester, EnvironmentSwitcherTapTarget.tapsToOpen);
      expect(find.text('Team code'), findsOneWidget);

      await enterCode(tester, 'wrong');
      expect(find.text('Team code'), findsNothing);
      expect(find.text(Environment.staging), findsNothing);
    }, variant: onAndroid);

    testWidgets(
      'not offered on web or desktop',
      (tester) async {
        await pumpLoginHeading(tester);
        await tapHeading(tester, EnvironmentSwitcherTapTarget.tapsToOpen);
        expect(find.text('Team code'), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets('not offered when the .env names no other environment', (
      tester,
    ) async {
      dotenv.testLoad(mergeWith: <String, String>{});
      await pumpLoginHeading(tester);
      await tapHeading(tester, EnvironmentSwitcherTapTarget.tapsToOpen);
      expect(find.text('Team code'), findsNothing);
    }, variant: onAndroid);

    testWidgets(
      "switching downloads the other environment's .env, erases the old "
      'storage and asks for a relaunch',
      (tester) async {
        await seedOldEnvironmentStorage(tester);
        await http.runWithClient(() async {
          await openPicker(tester);
          expect(find.text(Environment.production), findsOneWidget);
          await pick(tester, Environment.staging);
        }, () => _webApp(200, _stagingEnvFile));

        expect(
          Environment.appConfigurationStorage.read(PLocalKey.appConfigOverride),
          _staging.toJson(),
        );
        expect(GetStorage('class_storage').read('pending_code'), isNull);
        expect(find.text(relaunchNotice), findsOneWidget);

        // The relaunch notice can't be dismissed.
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(find.text(relaunchNotice), findsOneWidget);
      },
      variant: onAndroid,
    );

    for (final (failure, webApp) in [
      ('a failed download', () => _webApp(404, 'Not Found')),
      (
        'an incomplete file',
        () =>
            _webApp(200, _stagingEnvFile.replaceAll(RegExp('BOT_NAME=.*'), '')),
      ),
    ]) {
      testWidgets('$failure shows an error and changes nothing', (
        tester,
      ) async {
        await seedOldEnvironmentStorage(tester);
        await http.runWithClient(() async {
          await openPicker(tester);
          await pick(tester, Environment.staging);
        }, webApp);

        expect(find.byIcon(Icons.error_outline_outlined), findsOneWidget);

        // The switch resumes once the error is dismissed, and must stop there.
        await tester.tap(find.text('Close'));
        await settle(tester);
        expect(find.text(relaunchNotice), findsNothing);
        expect(
          Environment.appConfigurationStorage.read(PLocalKey.appConfigOverride),
          isNull,
        );
        expect(GetStorage('class_storage').read('pending_code'), 'abc123');
      }, variant: onAndroid);
    }

    testWidgets("picking the build's own environment removes the switch", (
      tester,
    ) async {
      await tester.runAsync(() => Environment.setAppConfigOverride(_staging));
      await http.runWithClient(() async {
        await openPicker(tester);
        await pick(tester, Environment.production);
      }, () => MockClient((_) async => fail('nothing to download')));

      expect(
        Environment.appConfigurationStorage.read(PLocalKey.appConfigOverride),
        isNull,
      );
      expect(Environment.isSwitched, isFalse);
      expect(find.text(relaunchNotice), findsOneWidget);
    }, variant: onAndroid);
  });

  group('badge', () {
    Future<void> pumpScreen(WidgetTester tester, VoidCallback onTap) =>
        tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            builder: (context, child) => EnvironmentBanner(child: child!),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: TextButton(onPressed: onTap, child: const Text('Close')),
              ),
            ),
          ),
        );

    testWidgets('hidden on an unswitched build', (tester) async {
      await pumpScreen(tester, () {});
      expect(find.byType(Banner), findsNothing);
    });

    testWidgets('names the environment and passes taps through', (
      tester,
    ) async {
      await tester.runAsync(() => Environment.setAppConfigOverride(_staging));
      var taps = 0;
      await pumpScreen(tester, () => taps++);

      final banner = tester.widget<Banner>(find.byType(Banner));
      expect(banner.message, 'STAGING');

      // The button sits under the banner's corner.
      await tester.tap(find.text('Close'));
      expect(taps, 1);
    });
  });
}
