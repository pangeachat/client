import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_chat_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_activity_chat_pangea_controller.dart';
import 'get_test_client.dart';

/// Submitting feedback on the activity summary regenerated it with no
/// acknowledgment, so the learner could not tell whether it went through
/// (#9243). A snackbar now says the feedback is being processed, then gives
/// the outcome, and a failure must not read like a success.
///
/// `FakeMatrixApi` has no handlers for this room, so the regeneration fails —
/// the failure path. The feedback dialog itself is skipped: its bot face is a
/// Rive animation, which needs native code a widget test does not load.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const roomId = '!feedback:fakeServer.notExisting';

  late Client client;

  setUpAll(() async {
    dotenv.testLoad(
      mergeWith: {'SYNAPSE_URL': 'https://fakeServer.notExisting'},
    );
    final tempDir = await Directory.systemTemp.createTemp('summary_feedback');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
  });

  setUp(() async => client = await getTestClient());

  tearDown(() => client.dispose());

  /// Submits feedback from a bare screen and returns the strings to look for.
  /// When [dismissWhileProcessing], the learner closes the "processing"
  /// snackbar before the regeneration finishes.
  Future<L10n> submitFeedback(
    WidgetTester tester, {
    bool dismissWhileProcessing = false,
  }) async {
    MatrixState.pangeaController = ActivityChatTestPangeaController();
    final controller = ActivityChatController(
      userID: userId,
      room: Room(id: roomId, client: client, membership: Membership.join),
      inputFocus: FocusNode(),
    );
    addTearDown(() => tester.runAsync(controller.dispose));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => controller.regenerateSummaryWithFeedback(
                context,
                'Too generic',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = L10n.of(tester.element(find.byType(IconButton)));

    await tester.tap(find.byType(IconButton));
    await tester.pump();

    // The wait is acknowledged before the regeneration finishes.
    expect(find.text(l10n.summaryFeedbackProcessing), findsOneWidget);

    if (dismissWhileProcessing) {
      // Let it finish sliding in, or the tap lands below the screen.
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(l10n.summaryFeedbackProcessing), findsNothing);
    }

    // The regeneration runs against the fake API on real async; the fake
    // clock advances between rounds so the snackbar swap can animate.
    final failed = find.text(l10n.summaryFeedbackFailed);
    for (var i = 0; i < 20 && failed.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    return l10n;
  }

  testWidgets('a failed feedback regeneration reports failure', (tester) async {
    final l10n = await submitFeedback(tester);

    expect(find.text(l10n.summaryFeedbackFailed), findsOneWidget);
    expect(find.text(l10n.summaryFeedbackProcessing), findsNothing);
    expect(find.text(l10n.summaryFeedbackReceived), findsNothing);

    // Let the snackbar's auto-dismiss timer run out.
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });

  testWidgets('dismissing the processing snackbar still shows the outcome', (
    tester,
  ) async {
    final l10n = await submitFeedback(tester, dismissWhileProcessing: true);

    expect(find.text(l10n.summaryFeedbackFailed), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 1));
  });
}
