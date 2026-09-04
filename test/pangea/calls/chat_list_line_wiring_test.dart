import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The chat-list line rule is only real if the client actually installs it.
///
/// `callCardMayTakeTheChatListLine` is pure and pinned directly by
/// `call_timeline_event_dedup_test.dart`. What that cannot show is that
/// anything calls it: the SDK only consults `shouldReplaceRoomLastEvent`, and
/// if the hook stops routing through the rule, every unit test still passes
/// while the chat list goes back to describing a different card than the
/// conversation draws.
///
/// A source check rather than a behavioural one, deliberately. `createClient`
/// builds a real database and a real sync, so exercising the hook through it
/// would cost far more than the wiring is worth. This proves the call exists,
/// not that the SDK honours it -- the SDK's side is pinned by the pub
/// dependency, not by us.
void main() {
  test('the client wires the chat-list line rule into the SDK hook', () {
    final source = File('lib/utils/client_manager.dart').readAsStringSync();

    final hook = source.indexOf('shouldReplaceRoomLastEvent:');
    expect(hook, isNonNegative, reason: 'the hook is still installed at all');

    // A window from the hook forward. Bounded by length rather than by the
    // next named parameter, because the parameter order is not ours to rely
    // on -- an earlier attempt anchored on one that turned out to sit ABOVE
    // this hook, and the substring threw.
    final body = source.substring(
      hook,
      hook + 500 < source.length ? hook + 500 : source.length,
    );

    expect(
      body,
      contains('callCardMayTakeTheChatListLine('),
      reason:
          'the hook must go through the shared rule, or the chat list and '
          'the conversation drift apart again',
    );
    expect(
      body,
      contains('isVisibleLastEvent'),
      reason: 'and must still exclude the event types it always excluded',
    );
  });
}
