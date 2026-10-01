import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/chat_event_list.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';

import 'perf_harness.dart';
import 'perf_output_io.dart'
    if (dart.library.js_interop) 'perf_output_web.dart';

/// Opens the joined chat [roomId], loads at least [minHistory] px of its
/// history, and returns the finder for its message list. Shared by the chat
/// and activity session scenarios.
Future<Finder> openChat(
  PerfRun run,
  String roomId, {
  required double minHistory,
}) async {
  final tester = run.tester;
  FluffyChatApp.router.go('/?left=chats,room:$roomId');
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

  // Scrolling never loads older messages (only "Load more" does), so load
  // them the same way first, before measuring, until there is room for the
  // drags; every run loads the same messages. A chat too short even then
  // would measure a list hitting its end.
  double loaded() =>
      tester.state<ScrollableState>(list).position.maxScrollExtent;
  final chat = tester.state<ChatController>(find.byType(ChatPageWithRoom));
  for (var i = 0; i < 5 && loaded() < minHistory; i++) {
    final before = loaded();
    await chat.requestHistory();
    await pause(tester, const Duration(seconds: 3));
    if (loaded() <= before) break;
  }
  if (loaded() < minHistory) {
    fail(
      '$roomId has ${loaded().round()} px of history; the scenario needs '
      'at least ${minHistory.round()}. Choose one with a longer history.',
    );
  }
  perfOutput('PERF chat open, ${loaded().round()} px of history');
  return list;
}

/// Measures five passes of scrolling the chat [list] that [openChat] opened,
/// in drags of [drag] px that reach twice that far into the history.
Future<List<Map<String, Object?>>> measureChatScroll(
  PerfRun run,
  Finder list, {
  required double drag,
}) async {
  final tester = run.tester;
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
        Offset(0, intoHistory ? drag : -drag),
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
}
