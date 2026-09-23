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
/// (#9243). The outcome now shows as a snackbar, and a failure must not read
/// like a success.
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

  testWidgets('a failed feedback regeneration reports failure', (tester) async {
    MatrixState.pangeaController = ActivityChatTestPangeaController();
    final controller = ActivityChatController(
      userID: userId,
      room: Room(id: roomId, client: client, membership: Membership.join),
      inputFocus: FocusNode(),
    );

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

    // The regeneration runs against the fake API on real async.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (find.byType(SnackBar).evaluate().isNotEmpty) break;
    }

    expect(find.text(l10n.summaryFeedbackFailed), findsOneWidget);
    expect(find.text(l10n.summaryFeedbackReceived), findsNothing);

    await tester.runAsync(controller.dispose);
    // Let the snackbar's auto-dismiss timer run out.
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });
}
