import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart' show Client;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/join_codes/qr_code_scan.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/account_updater.dart';
import 'package:fluffychat/routes/onboarding/avatar_provider.dart';
import 'package:fluffychat/routes/onboarding/course_provider.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/course_code_step_view.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/course_code_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/trial_info_provider.dart';
import '../get_test_client.dart';

class _RecordingCourseProvider extends MockCourseProvider {
  final List<String> joined = [];

  @override
  Future<String> joinSpaceWithCode(String code) async {
    joined.add(code);
    return super.joinSpaceWithCode(code);
  }
}

/// #9518 — the onboarding course-code step offers a QR scan on phones. A
/// course code read from the camera joins at once; any other QR code shows
/// the step's not-found error and the step stays usable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  final defaultOpen = QrCodeScan.open;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('course_code_qr');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    // Environment.frontendURL reads this override box, then dotenv.
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'FRONTEND_URL': 'https://app.pangea.chat'});
    client = await getTestClient();
  });

  tearDownAll(() => client.dispose());

  tearDown(() {
    QrCodeScan.open = defaultOpen;
    QrCodeScan.isWeb = kIsWeb;
  });

  late OnboardingStateController state;
  late _RecordingCourseProvider courseProvider;
  late int forwards;

  Future<L10n> pumpStep(WidgetTester tester) async {
    courseProvider = _RecordingCourseProvider();
    state = OnboardingStateController(
      accountUpdater: MockAccountUpdater(),
      courseProvider: courseProvider,
      avatarProvider: MockAvatarProvider(),
      trialInfoProvider: MockTrialInfoProvider(),
    );
    forwards = 0;
    final step = CourseCodeOnboardingStep(
      client: client,
      state: state,
      maxRemainingSteps: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: CourseCodeStepView(
            step: step,
            loading: false,
            error: null,
            hasNextStep: true,
            forward: () => forwards++,
            skip: () {},
          ),
        ),
      ),
    );
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    final l10n = L10n.of(tester.element(find.byType(CourseCodeStepView)));
    await tester.tap(find.widgetWithText(ElevatedButton, l10n.yes));
    await tester.pump();
    return l10n;
  }

  Finder scanButton(L10n l10n) =>
      find.widgetWithText(OutlinedButton, l10n.scanQrCode);

  testWidgets(
    'the scan button shows on phones',
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
    (tester) async {
      final l10n = await pumpStep(tester);
      expect(scanButton(l10n), findsOneWidget);
    },
  );

  testWidgets('the scan button never shows on web', (tester) async {
    QrCodeScan.isWeb = true;
    final l10n = await pumpStep(tester);
    expect(find.byType(TextField), findsOneWidget);
    expect(scanButton(l10n), findsNothing);
  });

  testWidgets('a scanned course link fills in the code and joins', (
    tester,
  ) async {
    QrCodeScan.open = (_) async =>
        const QrScanResult.scanned('https://app.pangea.chat/abc1234');
    final l10n = await pumpStep(tester);

    await tester.tap(scanButton(l10n));
    await tester.pump();

    expect(find.widgetWithText(TextField, 'abc1234'), findsOneWidget);
    expect(state.courseCode, 'abc1234');
    expect(forwards, 1);
    // The forward runs the step, which joins with the scanned code.
    await CourseCodeOnboardingStep(
      client: client,
      state: state,
      maxRemainingSteps: 1,
    ).execute();
    expect(courseProvider.joined, ['abc1234']);
    // Let the field's debounce settle.
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('a QR code that is not a course code shows not found', (
    tester,
  ) async {
    QrCodeScan.open = (_) async =>
        const QrScanResult.scanned('WIFI:S:home;T:WPA;P:secret;;');
    final l10n = await pumpStep(tester);

    await tester.tap(scanButton(l10n));
    await tester.pump();

    expect(find.text(l10n.courseCodeStepErrorMessage), findsOneWidget);
    expect(forwards, 0);
    expect(courseProvider.joined, isEmpty);
    // The step carries on: typing clears the error and keeps the field.
    await tester.enterText(find.byType(TextField), 'abc1234');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(l10n.courseCodeStepErrorMessage), findsNothing);
    expect(state.courseCode, 'abc1234');
    expect(scanButton(l10n), findsOneWidget);
  });

  testWidgets('a refused camera says so and leaves the field working', (
    tester,
  ) async {
    QrCodeScan.open = (_) async => const QrScanResult.cameraDenied();
    final l10n = await pumpStep(tester);

    await tester.tap(scanButton(l10n));
    await tester.pump();

    expect(find.text(l10n.scanQrCodeCameraDenied), findsOneWidget);
    expect(forwards, 0);
    await tester.enterText(find.byType(TextField), 'abc1234');
    await tester.pump(const Duration(milliseconds: 400));
    expect(state.courseCode, 'abc1234');
    // Let the snackbar run out.
    await tester.pump(const Duration(seconds: 10));
  });
}
