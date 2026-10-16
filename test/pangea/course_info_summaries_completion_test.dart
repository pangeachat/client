import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/features/room_summaries/room_summaries_model.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// The course page marks an activity complete from its session rooms'
/// `room_preview` summaries. A v3 session stores a thin
/// `{activity_id, version_id}` plan ref rather than an embedded plan, so the
/// summary's parsed plan is null and the activity id has to come from the ref.
/// Keying on the plan alone left every finished v3 activity unmarked.
void main() {
  const learner = '@learner:pangea.chat';

  Map<String, dynamic> v3Session({
    required String activityId,
    required bool archived,
  }) => {
    'membership_summary': {learner: 'join'},
    PangeaEventTypes.activityPlan: {
      'default': {
        'content': {
          ActivitySessionConstants.activityId: activityId,
          ActivitySessionConstants.versionId: 'v1',
        },
      },
    },
    PangeaEventTypes.activityRole: {
      'default': {
        'content': {
          'roles': {
            'r1': {
              'user_id': learner,
              'id': 'r1',
              'finished_at': '2026-10-01T10:00:00.000Z',
              if (archived) 'archived_at': '2026-10-01T10:05:00.000Z',
            },
          },
        },
      },
    },
  };

  CourseInfoSummariesModel modelFor(Map<String, dynamic> rooms) =>
      CourseInfoSummariesModel(
        RoomSummariesResponse.fromJson({
          'rooms': rooms,
        }, l1Code: 'en').summaries,
      );

  test('a saved v3 session marks its activity complete', () {
    final model = modelFor({
      '!done:pangea.chat': v3Session(activityId: 'a1', archived: true),
    });

    final summary = model.getRoomSummary('!done:pangea.chat')!;
    expect(summary.activityPlan, isNull, reason: 'v3 refs embed no plan');
    expect(model.hasCompletedActivity(learner, 'a1'), isTrue);
  });

  test('an unsaved v3 session does not', () {
    final model = modelFor({
      '!open:pangea.chat': v3Session(activityId: 'a1', archived: false),
    });

    expect(model.hasCompletedActivity(learner, 'a1'), isFalse);
  });

  test('another learner\'s saved session does not mark it for this one', () {
    final model = modelFor({
      '!done:pangea.chat': v3Session(activityId: 'a1', archived: true),
    });

    expect(model.hasCompletedActivity('@other:pangea.chat', 'a1'), isFalse);
  });
}
