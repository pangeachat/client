import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// Room state is open-ended, so a summaries batch can always contain a room
/// whose state this client version can't parse. That must cost only *that*
/// room: `RoomSummariesResponse.fromJson` feeds a single batched request of up
/// to 50 rooms, and a throw escaping it rejects the whole `Future.wait` in
/// `loadRoomSummaries` — the space's activity list then renders with no session
/// data at all (Sentry CLIENT-DG7, #8090).
void main() {
  Map<String, dynamic> membersOnly(String userId) => {
    'membership_summary': {userId: 'join'},
  };

  test(
    'a room that throws while parsing does not drop the rest of the batch',
    () {
      final response = RoomSummariesResponse.fromJson({
        'rooms': {
          '!before:pangea.chat': membersOnly('@ana:pangea.chat'),
          // Passes the `req != null` reference guard but is not a map, so
          // ActivityPlanRequest.fromJson throws the CLIENT-DG7 TypeError.
          '!bad:pangea.chat': {
            'membership_summary': {'@bo:pangea.chat': 'join'},
            PangeaEventTypes.activityPlan: {
              'default': {
                'content': {
                  ActivitySessionConstants.activityId: 'a1',
                  ActivitySessionConstants.activityPlanRequest: 'not-a-map',
                },
              },
            },
          },
          '!after:pangea.chat': membersOnly('@cy:pangea.chat'),
        },
      }, l1Code: 'en');

      expect(response.summaries.keys, [
        '!before:pangea.chat',
        '!after:pangea.chat',
      ]);
      expect(response.summaries['!after:pangea.chat']!.membershipSummary, {
        '@cy:pangea.chat': 'join',
      });
    },
  );

  test('a room whose payload is not a collection at all is skipped', () {
    // `value.isNotEmpty` itself throws here (NoSuchMethodError on an int), so
    // the emptiness check has to sit inside the per-room guard too.
    final response = RoomSummariesResponse.fromJson({
      'rooms': {
        '!junk:pangea.chat': 7,
        '!good:pangea.chat': membersOnly('@ana:pangea.chat'),
      },
    }, l1Code: 'en');

    expect(response.summaries.keys, ['!good:pangea.chat']);
  });

  test('empty room payloads are still omitted', () {
    final response = RoomSummariesResponse.fromJson({
      'rooms': {
        '!empty:pangea.chat': <String, dynamic>{},
        '!good:pangea.chat': membersOnly('@ana:pangea.chat'),
      },
    }, l1Code: 'en');

    expect(response.summaries.keys, ['!good:pangea.chat']);
  });
}
