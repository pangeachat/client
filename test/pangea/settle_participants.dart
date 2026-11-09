import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

/// Caches every member of [room] as never seen, the state a sync leaves, so
/// each avatar's presence read answers from memory (#9743).
///
/// An uncached read goes to the client's database and then caches what it
/// finds there with a write. Those calls run on real I/O, and each one
/// started on the fake clock also arms a ten-second lock-warning timer there.
/// A read still in flight when the test ends leaves that timer pending, then
/// writes to the database `tearDown` has closed. Whether one is still in
/// flight depends on how fast the runner is, so a fixed real-time wait
/// cannot settle it.
void cacheMemberPresence(Room room) {
  for (final id in room.states[EventTypes.RoomMember]!.keys) {
    // ignore: deprecated_member_use
    room.client.presences[id] = CachedPresence.neverSeen(id);
  }
}

/// Pumps until the participant list found by [list] has mounted and its
/// members have loaded, then settles.
///
/// L10n's delegate resolves from a deferred library on the fake clock, so
/// nothing is in the tree until a pump advances it. The members then load
/// over the test client, whose answers need real time to pass, and the
/// spinner shown meanwhile never lets `pumpAndSettle` return. So the two
/// clocks take turns until the spinner has stayed gone for several turns: a
/// course card's other loaders start theirs only after real I/O of their own,
/// so one spinner-free frame does not mean everything has finished.
Future<void> settle(WidgetTester tester, Finder list) async {
  bool loaded() =>
      list.evaluate().isNotEmpty &&
      find.byType(CircularProgressIndicator).evaluate().isEmpty;
  const quietTurnsNeeded = 5;
  var quietTurns = 0;
  for (var i = 0; i < 50 && quietTurns < quietTurnsNeeded; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 20)),
    );
    quietTurns = loaded() ? quietTurns + 1 : 0;
  }
  await tester.pumpAndSettle();
}
