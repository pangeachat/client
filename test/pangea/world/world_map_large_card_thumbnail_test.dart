import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/activity_participant_row.dart';
import 'package:fluffychat/routes/world/world_map_large_card.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/widgets/activity_star_row.dart';
import 'package:fluffychat/widgets/avatar.dart';
import '../get_test_client.dart';

/// #8278 — an ongoing-active card leads with the activity's thumbnail so it
/// reads as the same thing as that session's Chats-list tile, and it is the
/// ONLY card state with an image: joinable and ongoing-pending give that width
/// to their seat circles (world-map.instructions.md, "Pin display"). The
/// dismiss X moved off the title line to the card's top-left corner, inside the
/// border.
void main() {
  late Client client;

  const roomId = '!session:fakeServer.notExisting';
  final thumbnail = Uri.parse('https://example.org/stadium.png');

  const card = QuestActivityCard(
    activityId: 'a1',
    title: 'Meet a Fan at the Stadium',
    l2: 'es',
    cefr: 'b1',
    coordinates: [0, 0],
    learningObjectiveRefs: [],
    roleCount: 2,
  );

  setUpAll(() => dotenv.testLoad(mergeWith: {}));

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  /// A session room wearing the activity's picture, which is what
  /// `launchActivitySession` writes as the room avatar at launch.
  Room sessionRoom() {
    final room = Room(id: roomId, client: client, membership: Membership.join);
    room.setState(
      Event(
        type: EventTypes.RoomAvatar,
        content: {'url': thumbnail.toString()},
        stateKey: '',
        senderId: '@test:fakeServer.notExisting',
        eventId: '\$avatar',
        originServerTs: DateTime.utc(2026, 1, 1, 12),
        room: room,
      ),
    );
    return room;
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    required ActivityPinState state,
    Room? liveRoom,
    VoidCallback? onClose,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: WorldMapLargeCard(
              card: card,
              state: state,
              pinged: false,
              plan: null,
              liveRoom: liveRoom,
              starsEarned: 1,
              openSlots: 1,
              onTap: () {},
              onClose: onClose,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder thumbnailFinder() =>
      find.byWidgetPredicate((w) => w is Avatar && w.mxContent == thumbnail);

  /// Whether any avatar in the tree is drawing the activity's picture.
  bool showsThumbnail(WidgetTester tester) => tester
      .widgetList<Avatar>(find.byType(Avatar))
      .any((a) => a.mxContent == thumbnail);

  testWidgets('an ongoing-active card leads with the activity thumbnail', (
    tester,
  ) async {
    await pumpCard(
      tester,
      state: ActivityPinState.ongoingActive,
      liveRoom: sessionRoom(),
    );
    expect(showsThumbnail(tester), isTrue);
  });

  testWidgets('a joinable card shows no image, even with a live room', (
    tester,
  ) async {
    await pumpCard(
      tester,
      state: ActivityPinState.joinable,
      liveRoom: sessionRoom(),
    );
    expect(showsThumbnail(tester), isFalse);
  });

  testWidgets('an ongoing-pending card shows no image', (tester) async {
    await pumpCard(
      tester,
      state: ActivityPinState.ongoingPending,
      liveRoom: sessionRoom(),
    );
    expect(showsThumbnail(tester), isFalse);
  });

  testWidgets('an ongoing-active card with no room yet still renders', (
    tester,
  ) async {
    // The card is built before its room resolves; the thumbnail is simply
    // absent rather than a broken or placeholder image.
    await pumpCard(tester, state: ActivityPinState.ongoingActive);
    expect(showsThumbnail(tester), isFalse);
    expect(find.byType(WorldMapLargeCard), findsOneWidget);
  });

  testWidgets('the thumbnail is circular, like the chat list\'s avatar', (
    tester,
  ) async {
    await pumpCard(
      tester,
      state: ActivityPinState.ongoingActive,
      liveRoom: sessionRoom(),
    );
    // A null borderRadius is Avatar's own circle; a square would set one.
    expect(tester.widget<Avatar>(thumbnailFinder()).borderRadius, isNull);
  });

  group('one left edge', () {
    testWidgets('the title sits directly above the stars on a live card', (
      tester,
    ) async {
      await pumpCard(
        tester,
        state: ActivityPinState.ongoingActive,
        liveRoom: sessionRoom(),
        onClose: () {},
      );
      expect(
        tester.getTopLeft(find.text(card.title)).dx,
        moreOrLessEquals(
          tester.getTopLeft(find.byType(ActivityStarRow)).dx,
          epsilon: 0.5,
        ),
      );
    });

    testWidgets('and above the participant row on a joinable card', (
      tester,
    ) async {
      await pumpCard(
        tester,
        state: ActivityPinState.joinable,
        liveRoom: sessionRoom(),
        onClose: () {},
      );
      expect(
        tester.getTopLeft(find.text(card.title)).dx,
        moreOrLessEquals(
          tester.getTopLeft(find.byType(ActivityParticipantRow)).dx,
          epsilon: 0.5,
        ),
      );
    });
  });

  group('the dismiss X', () {
    testWidgets('sits in the gutter above the thumbnail, never in the title', (
      tester,
    ) async {
      await pumpCard(
        tester,
        state: ActivityPinState.ongoingActive,
        liveRoom: sessionRoom(),
        onClose: () {},
      );
      final close = tester.getRect(find.byType(IconButton));
      expect(
        close.right,
        lessThanOrEqualTo(tester.getTopLeft(find.text(card.title)).dx),
        reason: 'inline ahead of the title it pushed the text off its edge',
      );
      expect(
        close.top,
        lessThan(tester.getRect(thumbnailFinder()).center.dy),
        reason: 'up in the corner of the gutter',
      );
    });

    testWidgets('clears the content entirely on a state with no thumbnail', (
      tester,
    ) async {
      // The blank gutter is sized off the button, so the X can never land on
      // an available card's flag/level/party row the way it did on the title.
      await pumpCard(tester, state: ActivityPinState.available, onClose: () {});
      final closeRight = tester.getRect(find.byType(IconButton)).right;
      expect(
        closeRight,
        lessThanOrEqualTo(tester.getTopLeft(find.text(card.title)).dx),
      );
      expect(
        closeRight,
        lessThanOrEqualTo(tester.getTopLeft(find.text('B1')).dx),
      );
    });

    testWidgets('is hittable across the whole disc, not just its centre', (
      tester,
    ) async {
      // Reaching the corner by overhanging the card's Stack on negative
      // offsets left the button PAINTED but mostly un-hittable: hit-testing
      // stops at the parent's box whatever `Clip.none` allows. A centre tap
      // still landed, so only an off-centre one catches it (#8278).
      var closed = false;
      await pumpCard(
        tester,
        state: ActivityPinState.ongoingActive,
        liveRoom: sessionRoom(),
        onClose: () => closed = true,
      );
      final button = tester.getRect(find.byType(IconButton));
      await tester.tapAt(button.topLeft + const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
    });

    testWidgets('is absent without an onClose (the reuse knob)', (
      tester,
    ) async {
      await pumpCard(
        tester,
        state: ActivityPinState.ongoingActive,
        liveRoom: sessionRoom(),
      );
      expect(find.byIcon(Icons.close), findsNothing);
    });
  });
}
