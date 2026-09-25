import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/main.dart' as app;
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/chat_event_list.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';

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

    FluffyChatApp.router.go('/?left=chats,room:$chatId');
    final lists = find.descendant(
      of: find.byType(ChatEventList),
      matching: find.byType(Scrollable),
    );
    await waitFor(
      tester,
      () => lists.evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
      failure: 'The chat did not open.',
    );
    final list = lists.first;
    // Let the messages and their media settle before measuring.
    await pause(tester, const Duration(seconds: 8));

    // The drags reach 800 px into the history (activity chats, the common
    // kind, hold about 1,300 px). Scrolling never loads older
    // messages (only "Load more" does), so load them the same way first,
    // before measuring, until there is room to scroll; every run loads the
    // same messages. A chat too short even then would measure a list
    // hitting its end.
    double loaded() =>
        tester.state<ScrollableState>(list).position.maxScrollExtent;
    final chat = tester.state<ChatController>(find.byType(ChatPageWithRoom));
    for (var i = 0; i < 5 && loaded() < 1000; i++) {
      final before = loaded();
      await chat.requestHistory();
      await pause(tester, const Duration(seconds: 3));
      if (loaded() <= before) break;
    }
    if (loaded() < 1000) {
      fail(
        '$chatId has ${loaded().round()} px of history; the scenario needs '
        'at least 1,000. Choose a chat with a longer history.',
      );
    }
    perfOutput('PERF chat open, ${loaded().round()} px of history');

    final passes = <Map<String, Object?>>[];
    for (var pass = 0; pass < 5; pass++) {
      final recorder = FrameRecorder()..start();
      // The list is reversed: dragging down moves into older messages. Two
      // drags in, then back and forth over the same stretch, so every pass
      // scrolls the same messages.
      for (var i = 0; i < 16; i++) {
        final intoHistory = i < 2 || i.isOdd;
        await tester.timedDrag(
          list,
          Offset(0, intoHistory ? 400 : -400),
          const Duration(milliseconds: 200),
        );
        await pause(tester, const Duration(milliseconds: 150));
      }
      final timings = await recorder.stop(tester);
      if (timings.length < 30) {
        fail(
          'Pass ${pass + 1} drew ${timings.length} frames: the drags did not '
          'scroll the chat.',
        );
      }
      passes.add(summarize(timings, run.budgetMs));
      perfOutput('PERF pass ${pass + 1}: ${passes.last}');
      // Back to the newest message, so the next pass starts where this one did.
      await tester.timedDrag(
        list,
        const Offset(0, -1000),
        const Duration(milliseconds: 300),
      );
      await pause(tester, const Duration(seconds: 2));
    }
    return passes;
  },
);
