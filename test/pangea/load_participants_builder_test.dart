import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/spaces/load_participants_builder.dart';
import 'get_test_client.dart';

/// `LoadParticipantsBuilder.loading` starts true and is only cleared by the
/// participant fetch. A room that skips the fetch — one the user has left, or
/// a null room — must still clear it, or consumers that gate on `loading`
/// (the chat page's spinner) spin forever (#8148).
void main() {
  late Client client;

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  Future<LoadParticipantsBuilderState> pumpBuilder(
    WidgetTester tester,
    Room? room,
  ) async {
    late LoadParticipantsBuilderState state;
    await tester.pumpWidget(
      MaterialApp(
        home: LoadParticipantsBuilder(
          room: room,
          builder: (context, s) {
            state = s;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    return state;
  }

  testWidgets('a left room clears loading instead of spinning forever '
      '(#8148)', (tester) async {
    final room = Room(
      id: '!left:fakeServer.notExisting',
      membership: Membership.leave,
      client: client,
    );

    final state = await pumpBuilder(tester, room);
    expect(state.loading, isFalse);
  });

  testWidgets('a null room clears loading', (tester) async {
    final state = await pumpBuilder(tester, null);
    expect(state.loading, isFalse);
  });
}
