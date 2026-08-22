import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_record.dart';
import 'package:fluffychat/routes/chat/calls/call_timeline_event.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import '../get_test_client.dart';

/// The first-per-key rule, pinned directly.
///
/// Matrix transaction ids dedup PER DEVICE, so the writer and the survivor
/// racing across the settle window can genuinely both post a card for one
/// call. The renderer is the idempotent receiver: only the FIRST card per
/// key in timeline order draws, on every client identically.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late Room room;

  setUpAll(() async {
    client = await getTestClient();
    room = Room(id: '!r:server', client: client);
  });

  tearDownAll(() => client.dispose());

  Event card(
    String id, {
    String? key,
    int ts = 1000,
    EventStatus status = EventStatus.synced,
  }) => Event(
    type: PangeaEventTypes.call,
    content: {
      'msgtype': PangeaEventTypes.call,
      'body': 'Voice call',
      'answered': true,
      CallRecord.callKeyField: ?key,
    },
    senderId: '@a:server',
    eventId: id,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
    room: room,
    status: status,
  );

  test('the second card for one call is the duplicate', () {
    final first = card(r'$one', key: 'k', ts: 1000);
    final second = card(r'$two', key: 'k', ts: 2000);
    final all = [first, second];
    expect(CallTimelineEvent.isDuplicateOfEarlier(first, all), isFalse);
    expect(CallTimelineEvent.isDuplicateOfEarlier(second, all), isTrue);
  });

  test('the same moment is settled by event id, identically everywhere', () {
    final a = card(r'$aaa', key: 'k', ts: 1000);
    final b = card(r'$bbb', key: 'k', ts: 1000);
    // Whatever order the list arrives in, the same one survives.
    for (final all in [
      [a, b],
      [b, a],
    ]) {
      expect(CallTimelineEvent.isDuplicateOfEarlier(a, all), isFalse);
      expect(CallTimelineEvent.isDuplicateOfEarlier(b, all), isTrue);
    }
  });

  test('different keys are different calls', () {
    final one = card(r'$one', key: 'k1', ts: 1000);
    final two = card(r'$two', key: 'k2', ts: 2000);
    final all = [one, two];
    expect(CallTimelineEvent.isDuplicateOfEarlier(two, all), isFalse);
  });

  test('keyless legacy cards always draw', () {
    final legacy1 = card(r'$one', ts: 1000);
    final legacy2 = card(r'$two', ts: 2000);
    final all = [legacy1, legacy2];
    expect(CallTimelineEvent.isDuplicateOfEarlier(legacy1, all), isFalse);
    expect(CallTimelineEvent.isDuplicateOfEarlier(legacy2, all), isFalse);
  });

  test('a card that never sent cannot suppress the one that did', () {
    // The failed optimistic echo is already hidden by its own rule; letting
    // it ALSO count as "the first card" would hide the real one and the call
    // would vanish from both.
    final failed = card(
      r'$dead',
      key: 'k',
      ts: 1000,
      status: EventStatus.error,
    );
    final real = card(r'$real', key: 'k', ts: 2000);
    final all = [failed, real];
    expect(CallTimelineEvent.isDuplicateOfEarlier(real, all), isFalse);
  });
}
