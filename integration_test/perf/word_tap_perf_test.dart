import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/main.dart' as app;
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/html_message.dart';
import 'package:fluffychat/routes/chat/toolbar/message_selection_overlay.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';

import 'chat_scroll.dart';
import 'perf_harness.dart';
import 'perf_output_io.dart'
    if (dart.library.js_interop) 'perf_output_web.dart';

/// How many words each pass taps, the same ones every pass.
const _words = 3;

/// Performance benchmark: tapping the same words in a chat the tester names,
/// opening the message's word card and closing it again. Needs word audio and
/// read aloud on click turned off: either plays audio on every tap and
/// records it on the account, and device audio varies between runs. How to
/// run it: [benchmark].
///
///   fvm flutter drive --profile --keep-app-running -d DEVICE_ID
///     --dart-define=PERF_CHAT='!roomid:server'
///     --driver=test_driver/perf_driver.dart
///     --target=integration_test/perf/word_tap_perf_test.dart
///
/// On web: web_runner.js --param 'chat=!roomid:server'.
void main() => benchmark(
  'word_tap',
  warmupPasses: 1,
  body: (run) async {
    final tester = run.tester;
    const definedChat = String.fromEnvironment('PERF_CHAT');
    final chatId = run.urlParameters['chat'] ?? definedChat;
    run.target = chatId;
    if (chatId.isEmpty) {
      fail(
        'Name the chat whose words to tap: --dart-define=PERF_CHAT=<room id>, '
        'or on web --param chat=<room id>.',
      );
    }

    app.main();
    await waitFor(
      tester,
      () => isSignedIn(tester),
      timeout: const Duration(seconds: 60),
      failure: notSignedIn,
    );
    final user = MatrixState.pangeaController.userController;
    await waitFor(
      tester,
      () => user.initCompleter.isCompleted,
      timeout: const Duration(seconds: 30),
      failure: "The account's settings did not load.",
    );
    final client = tester.state<MatrixState>(find.byType(Matrix)).client;
    // Signed in comes before the first sync has loaded the chats.
    await waitFor(
      tester,
      () => client.getRoomById(chatId)?.membership == Membership.join,
      timeout: const Duration(seconds: 30),
      failure: '$chatId is not a chat this account has joined.',
    );
    perfOutput('PERF signed in');

    await openChat(run, chatId, minHistory: 0);
    // Checked once the first sync is in: a setting changed on another device
    // arrives with it, after the copy cached on this one has loaded.
    for (final (setting, name) in [
      (ToolSetting.audioWords, 'word audio'),
      (ToolSetting.audioOnMessageClick, 'read aloud on click'),
    ]) {
      if (user.userToolSetting(setting)) {
        fail(
          'Turn off $name in the learning settings: it plays audio on every '
          'tap and records it on the account.',
        );
      }
    }
    final chat = tester.state<ChatController>(find.byType(ChatPageWithRoom));
    // The words to tap: the first few on screen, in the messages' order.
    // Only a message that already has its words split out shows them as
    // separate tap targets, so tapping never asks the server to split one.
    final words = find
        .descendant(
          of: find.byType(HtmlMessage),
          matching: find.byType(HoverBuilder),
        )
        .hitTestable();
    if (words.evaluate().length < _words) {
      fail(
        '$chatId shows ${words.evaluate().length} words to tap; the scenario '
        'needs $_words. Choose a chat with text messages in the target language, such as an activity session.',
      );
    }
    final overlay = find.byType(MessageSelectionOverlay);

    final passes = <Map<String, Object?>>[];
    for (var pass = 0; pass < 5; pass++) {
      final recorder = FrameRecorder()..start();
      for (var i = 0; i < _words; i++) {
        await recorder.action('open card', () async {
          await tester.tap(words.at(i));
          await waitFor(
            tester,
            () => overlay.evaluate().isNotEmpty,
            timeout: const Duration(seconds: 10),
            failure: 'Tapping word ${i + 1} opened no word card.',
          );
          // The card's entrance and its lookups.
          await pause(tester, const Duration(milliseconds: 1500));
        });
        // Closed the way the backdrop closes it.
        await recorder.action('close card', () async {
          chat.clearSelectedEvents();
          await waitFor(
            tester,
            () => overlay.evaluate().isEmpty,
            timeout: const Duration(seconds: 10),
            failure: 'The word card for word ${i + 1} did not close.',
          );
          await pause(tester, const Duration(milliseconds: 700));
        });
      }
      final timings = await recorder.stop(tester);
      passes.add(summarize(timings, run.budgetMs, actions: recorder.actions));
      perfOutput('PERF pass ${pass + 1}: ${passes.last}');
      await pause(tester, const Duration(seconds: 2));
    }
    return passes;
  },
);
