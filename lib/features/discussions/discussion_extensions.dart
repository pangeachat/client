import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';

/// The names a discussion travels under (#9647). A discussion is listed like
/// an activity (its plan's mode marks it) but runs as a plain group chat.
abstract class DiscussionIds {
  /// The plan mode that marks a listed activity as a discussion.
  static const String mode = 'discussion';

  /// Prefix of a dummy discussion's activity id.
  static const String prefix = 'discussion-';

  /// The state event a discussion room carries: which discussion, which
  /// Mission, which course.
  static const String stateEvent = 'pangea.discussion';

  /// How many members a discussion room takes before the next learner is
  /// put in a new one.
  static const int roomCapacity = 20;

  /// Per-room account data holding the learner's own progress in a
  /// discussion: which questions they have answered, and whether they ended.
  static const String progressAccountData = 'pangea.discussion_progress';
}

extension DiscussionPlanExtension on ActivityPlanModel {
  bool get isDiscussion => req.mode == DiscussionIds.mode;

  /// The photo a discussion shows, and its room's avatar.
  Uri? get discussionImageUrl {
    final hero = heroBlock?.displayUrl();
    return hero != null ? Uri.tryParse(hero) : imageURL;
  }
}

extension DiscussionCardExtension on QuestActivityCard {
  bool get isDiscussion => mode == DiscussionIds.mode;
}

extension DiscussionRoomExtension on Room {
  /// The discussion this room is a chat for, from its room type; null for
  /// every other room.
  String? get discussionActivityId {
    final type = roomType;
    const prefix = '${PangeaRoomTypes.discussion}:';
    if (type == null || !type.startsWith(prefix)) return null;
    return type.substring(prefix.length);
  }
}

/// The learner's own progress in one discussion room (#9647): the questions
/// they have answered, by index, and whether they have ended. Kept per player
/// in room account data, which any member may write; a discussion has no
/// roles to hang awards on. Prototype: the full version moves awards into
/// room state the orchestrator writes.
class DiscussionProgress {
  final Set<int> answered;
  final bool ended;

  const DiscussionProgress({this.answered = const {}, this.ended = false});

  static DiscussionProgress fromJson(Map<String, Object?>? json) =>
      DiscussionProgress(
        answered: {
          for (final i in (json?['answered'] as List?) ?? const [])
            if (i is int) i,
        },
        ended: json?['ended'] == true,
      );

  Map<String, Object?> toJson() => {
    'answered': answered.toList()..sort(),
    'ended': ended,
  };

  /// The first question not yet answered, or null when every one is.
  int? currentOf(int questionCount) {
    for (var i = 0; i < questionCount; i++) {
      if (!answered.contains(i)) return i;
    }
    return null;
  }
}

extension DiscussionProgressRoomExtension on Room {
  DiscussionProgress get discussionProgress => DiscussionProgress.fromJson(
    roomAccountData[DiscussionIds.progressAccountData]?.content,
  );

  Future<void> setDiscussionProgress(DiscussionProgress progress) =>
      client.setAccountDataPerRoom(
        client.userID!,
        id,
        DiscussionIds.progressAccountData,
        progress.toJson(),
      );
}

extension DiscussionClientExtension on Client {
  /// The learner's joined rooms for [activityId] — normally one; more only if
  /// they joined a second when the first was full.
  List<Room> discussionRoomsFor(String activityId) => [
    for (final room in rooms)
      if (room.membership == Membership.join &&
          room.discussionActivityId == activityId)
        room,
  ];
}

extension DiscussionAwardRoomExtension on Room {
  /// Prototype award rule (#9647): the learner's target-language message
  /// answers the question in front of them, which earns its goal and brings
  /// up the next. The full version awards on the orchestrator's judgement,
  /// relative to the learner's level.
  Future<void> answerCurrentDiscussionQuestion(int questionCount) async {
    if (discussionActivityId == null) return;
    final progress = discussionProgress;
    if (progress.ended) return;
    final current = progress.currentOf(questionCount);
    if (current == null) return;
    await setDiscussionProgress(
      DiscussionProgress(
        answered: {...progress.answered, current},
        ended: progress.ended,
      ),
    );
  }
}
