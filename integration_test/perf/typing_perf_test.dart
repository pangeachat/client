import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/bot/bot_room_extension.dart';
import 'package:fluffychat/main.dart' as app;
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';

import 'perf_harness.dart';
import 'perf_output_io.dart'
    if (dart.library.js_interop) 'perf_output_web.dart';

/// A fixed sentence, typed the same way in every pass and every run.
const _sentence = 'Hola, esta tarde quiero practicar un poco de español.';

/// Writing assistance starts 10 s after the last keystroke
/// (ChoreoConstants.msBeforeIGCStart), and every keystroke restarts that
/// wait. A pass types steadily and clears the text right after the last
/// keystroke, so the scenario never calls the backend.
const _keystroke = Duration(milliseconds: 120);

/// Performance benchmark: typing a fixed sentence into the composer of the
/// chat with the bot, then clearing it before writing assistance starts. The
/// bot's chat, so typing notifications reach no person. How to run it:
/// [benchmark].
///
///   fvm flutter drive --profile --keep-app-running -d DEVICE_ID
///     --driver=test_driver/perf_driver.dart
///     --target=integration_test/perf/typing_perf_test.dart
void main() => benchmark(
  'typing',
  warmupPasses: 1,
  body: (run) async {
    final tester = run.tester;
    app.main();
    await waitFor(
      tester,
      () => isSignedIn(tester),
      timeout: const Duration(seconds: 60),
      failure: notSignedIn,
    );
    final client = tester.state<MatrixState>(find.byType(Matrix)).client;
    // Signed in comes before the first sync has loaded the rooms.
    Room? botChat() => client.rooms.firstWhereOrNull(
      (r) => r.isBotDM && r.membership == Membership.join,
    );
    await waitFor(
      tester,
      () => botChat() != null,
      timeout: const Duration(seconds: 30),
      failure: 'This account has joined no chat with the bot.',
    );
    final roomId = botChat()!.id;
    run.target = roomId;
    perfOutput('PERF signed in; chat with the bot: $roomId');

    FluffyChatApp.router.go('/?left=chats,room:$roomId');
    final page = find.byType(ChatPageWithRoom);
    await waitFor(
      tester,
      () => page.evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
      failure: 'The chat with the bot did not open.',
    );
    final chat = tester.state<ChatController>(page);
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.controller == chat.sendController,
    );
    await waitFor(
      tester,
      () => field.evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
      failure: 'The chat with the bot has no composer.',
    );
    // Let the chat settle before measuring.
    await pause(tester, const Duration(seconds: 8));

    // The benchmark binding leaves text input to the real keyboard, which a
    // test cannot type on. Flutter's test keyboard sends the same editing
    // updates through the platform text channel, so the field, its
    // controller and writing assistance's listeners all see real typing.
    tester.testTextInput.register();
    try {
      await tester.showKeyboard(field);
      final passes = <Map<String, Object?>>[];
      for (var pass = 0; pass < 5; pass++) {
        var lastKey = DateTime.now();
        var longestGap = Duration.zero;
        void keyed() {
          final now = DateTime.now();
          if (now.difference(lastKey) > longestGap) {
            longestGap = now.difference(lastKey);
          }
          lastKey = now;
        }

        final recorder = FrameRecorder()..start();
        for (var i = 1; i <= _sentence.length; i++) {
          final text = _sentence.substring(0, i);
          await recorder.action('keystroke', () async {
            tester.testTextInput.updateEditingValue(
              TextEditingValue(
                text: text,
                selection: TextSelection.collapsed(offset: text.length),
              ),
            );
            keyed();
            await pause(tester, _keystroke);
          });
        }
        tester.testTextInput.updateEditingValue(TextEditingValue.empty);
        keyed();
        await pause(tester, const Duration(milliseconds: 500));
        final timings = await recorder.stop(tester);
        if (longestGap > const Duration(seconds: 9)) {
          fail(
            'Pass ${pass + 1} paused ${longestGap.inSeconds} s between '
            'keystrokes: writing assistance may have started, which calls '
            'the backend.',
          );
        }
        if (timings.length < 30) {
          fail('Pass ${pass + 1} drew ${timings.length} frames while typing.');
        }
        passes.add(summarize(timings, run.budgetMs, actions: recorder.actions));
        perfOutput('PERF pass ${pass + 1}: ${passes.last}');
        await pause(tester, const Duration(seconds: 2));
      }
      return passes;
    } finally {
      tester.testTextInput.updateEditingValue(TextEditingValue.empty);
      tester.testTextInput.unregister();
    }
  },
);
