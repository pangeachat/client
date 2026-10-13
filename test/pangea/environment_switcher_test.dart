import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/constants/local.key.dart';
import 'package:fluffychat/pangea/common/widgets/environment_banner.dart';
import 'package:fluffychat/routes/home/login/environment_switcher.dart';

/// The hidden environment switcher (deployment.instructions.md § Environment
/// switcher): the environment list, the switch state, the gesture and code,
/// the storage wipe, and the badge.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  final staging = Environment.switchableEnvironments.firstWhere(
    (environment) => environment.environment == Environment.staging,
  );

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
    // A production build: its .env never sets ENVIRONMENT.
    dotenv.testLoad(mergeWith: <String, String>{});
    await Environment.setAppConfigOverride(null);
  });

  group('switchable environments', () {
    test('are production and staging', () {
      expect(Environment.switchableEnvironments.map((e) => e.environment), [
        Environment.production,
        Environment.staging,
      ]);
    });

    test('each names every value that differs between environments', () {
      for (final environment in Environment.switchableEnvironments) {
        final values = {
          'frontendURL': environment.frontendURL,
          'synapseURL': environment.synapseURL,
          'choreoApi': environment.choreoApi,
          'teacherBffApi': environment.teacherBffApi,
          'stripeManagementUrl': environment.stripeManagementUrl,
          'botName': environment.botName,
        };
        for (final MapEntry(:key, :value) in values.entries) {
          expect(
            value,
            isNotEmpty,
            reason: '${environment.environment} leaves out $key',
          );
        }
      }
    });

    test('each points Sentry at its own name', () async {
      for (final environment in Environment.switchableEnvironments) {
        await Environment.setAppConfigOverride(environment);
        expect(Environment.sentryEnvironment, environment.environment);
      }
    });
  });

  group('switch state', () {
    test('a production build with no switch talks to production', () {
      expect(Environment.buildEnvironment, Environment.production);
      expect(Environment.activeEnvironment, Environment.production);
      expect(Environment.isSwitched, isFalse);
    });

    test('switching a production build to staging', () async {
      await Environment.setAppConfigOverride(staging);
      expect(Environment.activeEnvironment, Environment.staging);
      expect(Environment.isSwitched, isTrue);
      expect(Environment.synapseURL, staging.synapseURL);
    });

    test('a staging build switched to staging is not switched', () async {
      dotenv.testLoad(mergeWith: {'ENVIRONMENT': Environment.staging});
      await Environment.setAppConfigOverride(staging);
      expect(Environment.isSwitched, isFalse);
    });

    test('a switched build reads the switched CMS', () async {
      await Environment.setAppConfigOverride(staging);
      expect(Environment.cmsApi, staging.choreoApi);
    });
  });

  group('tap target', () {
    final onAndroid = TargetPlatformVariant.only(TargetPlatform.android);

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

    testWidgets(
      'the code and a pick switch, erase the old storage and ask for a relaunch',
      (tester) async {
        await tester.runAsync(() async {
          await GetStorage.init('class_storage');
          await GetStorage('class_storage').write('pending_code', 'abc123');
        });

        await pumpLoginHeading(tester);
        await tapHeading(tester, EnvironmentSwitcherTapTarget.tapsToOpen);
        await enterCode(tester, EnvironmentSwitcherTapTarget.teamCode);
        expect(find.text(Environment.production), findsOneWidget);

        await tester.tap(find.text(Environment.staging));
        // The switch writes and erases files, which fake time never finishes.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await tester.pumpAndSettle();

        expect(Environment.activeEnvironment, Environment.staging);
        expect(
          Environment.appConfigurationStorage.read(PLocalKey.appConfigOverride),
          staging.toJson(),
        );
        expect(GetStorage('class_storage').read('pending_code'), isNull);
        expect(
          find.text(
            'Close the app completely and open it again to finish switching.',
          ),
          findsOneWidget,
        );

        // The relaunch notice can't be dismissed.
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Close the app completely and open it again to finish switching.',
          ),
          findsOneWidget,
        );
      },
      variant: onAndroid,
    );

    testWidgets("picking the build's own environment removes the switch", (
      tester,
    ) async {
      await tester.runAsync(() => Environment.setAppConfigOverride(staging));
      await pumpLoginHeading(tester);
      await tapHeading(tester, EnvironmentSwitcherTapTarget.tapsToOpen);
      await enterCode(tester, EnvironmentSwitcherTapTarget.teamCode);

      await tester.tap(find.text(Environment.production));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pumpAndSettle();

      expect(
        Environment.appConfigurationStorage.read(PLocalKey.appConfigOverride),
        isNull,
      );
      expect(Environment.isSwitched, isFalse);
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
      await tester.runAsync(() => Environment.setAppConfigOverride(staging));
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
