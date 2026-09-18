import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/chat_event_list.dart';

/// #8837: the timeline sliver has [ChatEventList.leadingRowCount] rows before
/// the first event, and its item builder subtracts that many from the sliver
/// index. The key-to-index callback used to add back only one, so on every
/// list rebuild Flutter moved each keyed row to a slot whose builder produced
/// a different key, discarded the row's element, and inflated a fresh one.
/// Every State inside the row restarted — the avatar's PresenceBuilder went
/// back to "unknown" for a frame and the dot blinked on each send.
///
/// The real list needs a live ChatController and timeline, so this drives a
/// `ListView.custom` with the same leading-row layout and the real callback,
/// and checks that a row's State survives both a plain rebuild and a newly
/// prepended event.
class _EventRow extends StatefulWidget {
  const _EventRow({required this.eventId, super.key});

  final String eventId;

  @override
  State<_EventRow> createState() => _EventRowState();
}

class _EventRowState extends State<_EventRow> {
  @override
  Widget build(BuildContext context) => Text(widget.eventId);
}

Widget _host(List<String> eventIds) {
  final indexByEventId = {
    for (var i = 0; i < eventIds.length; i++) eventIds[i]: i,
  };
  return MaterialApp(
    home: ListView.custom(
      reverse: true,
      childrenDelegate: SliverChildBuilderDelegate(
        (context, i) {
          if (i < ChatEventList.leadingRowCount) {
            return const SizedBox(height: 10);
          }
          final eventId = eventIds[i - ChatEventList.leadingRowCount];
          return _EventRow(key: ValueKey(eventId), eventId: eventId);
        },
        childCount: eventIds.length + ChatEventList.leadingRowCount,
        findChildIndexCallback: (key) =>
            ChatEventList.findChildIndexCallback(key, indexByEventId),
      ),
    ),
  );
}

void main() {
  const rowA = ValueKey('\$a');

  testWidgets('a list rebuild keeps each event row\'s State', (tester) async {
    await tester.pumpWidget(_host(['\$a', '\$b']));
    final before = tester.state(find.byKey(rowA));

    // A new delegate instance is what every ChatEventList rebuild hands the
    // sliver; the row set is unchanged.
    await tester.pumpWidget(_host(['\$a', '\$b']));

    expect(tester.state(find.byKey(rowA)), same(before));
  });

  testWidgets('a newly sent message shifts rows without remounting them', (
    tester,
  ) async {
    await tester.pumpWidget(_host(['\$a', '\$b']));
    final before = tester.state(find.byKey(rowA));

    // Newest event first, as in the timeline: the send lands at index 0 and
    // every existing row moves down one sliver slot.
    await tester.pumpWidget(_host(['\$sent', '\$a', '\$b']));

    expect(tester.state(find.byKey(rowA)), same(before));
    expect(find.text('\$sent'), findsOneWidget);
  });
}
