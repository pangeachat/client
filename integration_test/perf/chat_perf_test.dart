import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/main.dart' as app;
import 'package:fluffychat/widgets/matrix.dart';

import 'chat_scroll.dart';
import 'perf_harness.dart';
import 'perf_output_io.dart'
    if (dart.library.js_interop) 'perf_output_web.dart';

/// Performance benchmark: scrolling one chat's message history. The tester
/// names the chat, so every run of a comparison measures the same one: a
/// chat picked automatically could change between rounds when a message
/// arrives. How to run it: [benchmark].
///
///   fvm flutter drive --profile --keep-app-running -d DEVICE_ID
///     --dart-define=PERF_CHAT='!roomid:server'
///     --driver=test_driver/perf_driver.dart
///     --target=integration_test/perf/chat_perf_test.dart
///
/// On web: web_runner.js --param 'chat=!roomid:server'.
void main() => benchmark(
  'chat_scroll',
  warmupPasses: 1,
  body: (run) async {
    final tester = run.tester;
    const definedChat = String.fromEnvironment('PERF_CHAT');
    final chatId = run.urlParameters['chat'] ?? definedChat;
    run.target = chatId;

    app.main();
    await waitFor(
      tester,
      () => isSignedIn(tester),
      timeout: const Duration(seconds: 60),
      failure: notSignedIn,
    );
    final client = tester.state<MatrixState>(find.byType(Matrix)).client;
    if (chatId.isEmpty) {
      // List the account's chats so the tester can choose one.
      for (final r in client.rooms.where(
        (r) => !r.isSpace && r.membership == Membership.join,
      )) {
        perfOutput('PERF chat: ${r.id}  ${r.getLocalizedDisplayname()}');
      }
      fail(
        'Name the chat to scroll: --dart-define=PERF_CHAT=<room id>, or on '
        'web --param chat=<room id>. Chats on this account are listed above.',
      );
    }
    // Signed in comes before the first sync has loaded the chats; give it time.
    await waitFor(
      tester,
      () => client.getRoomById(chatId)?.membership == Membership.join,
      timeout: const Duration(seconds: 30),
      failure: '$chatId is not a chat this account has joined.',
    );
    perfOutput('PERF signed in');

    // Drags reach 800 px into the history (activity chats, the common kind,
    // hold about 1,300 px).
    final list = await openChat(run, chatId, minHistory: 1000);
    return measureChatScroll(run, list, drag: 400);
  },
);
