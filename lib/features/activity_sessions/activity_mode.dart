import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The activity modes, and every way a mode changes how its activities look
/// and run (#9647). Screens ask the mode a question ("does it name roles?")
/// rather than checking for one mode, so a new mode is added here: give it a
/// value, and the exhaustive switches below name every answer it needs.
enum ActivityMode {
  /// Players take roles and work toward their own goals. Activities made in
  /// the older modes (Debate, Decision Making, 20 Questions, Conversation)
  /// are re-categorized as roleplay and play as one (#700).
  roleplay,

  /// A course's shared room of students talking about one photo and a few
  /// questions, with the bot facilitating (org activities doc, "Mode: Discussion").
  discussion;

  /// The plan `mode` value of a discussion, compared case-insensitively.
  static const String _discussionPlanMode = 'discussion';

  /// A discussion's one shared role; every student's seat is on it.
  static const String discussionRoleId = 'participant';

  /// Whether [key] in a room's `pangea.activity_roles` is a discussion seat:
  /// synapse keys each student's seat on the shared role by student
  /// (`participant:<user id>`), where a roleplay keys a seat by its role id.
  /// Every discussion room has one from its creation, so this tells a
  /// discussion's preview from a roleplay's before its plan loads.
  static bool isDiscussionSeatKey(String key) =>
      key.startsWith('$discussionRoleId:');

  /// A plan's mode from its shape: a discussion only when its mode is
  /// "discussion" AND its roles are exactly the one shared `participant`
  /// role. The v1 planner took free-text modes, so a roleplay-shaped plan
  /// can carry "Discussion" and must stay a roleplay. Unknown roles (a card
  /// whose roles weren't projected) read as roleplay.
  static ActivityMode fromShape({
    required String? mode,
    required Iterable<String> roleIds,
  }) =>
      mode?.toLowerCase() == _discussionPlanMode &&
          roleIds.length == 1 &&
          roleIds.first == discussionRoleId
      ? discussion
      : roleplay;

  /// The tag on its cards.
  String label(L10n l10n) => switch (this) {
    roleplay => l10n.roleplayLabel,
    discussion => l10n.discussionLabel,
  };

  /// The screen-reader name of an activity's card or pin.
  String titleLabel(L10n l10n, String title) => switch (this) {
    roleplay => l10n.activityLabel(title),
    discussion => l10n.discussionCardSemantics(title),
  };

  /// What a learner in one of its live sessions is called, in place of the
  /// session state's own name; null keeps that name ("Ongoing"). A discussion
  /// has no session that starts and ends, so the learner has "Joined" it.
  String? joinedLabel(L10n l10n) => switch (this) {
    roleplay => null,
    discussion => l10n.discussionJoined,
  };

  /// The icon beside that tag, and the glyph on its map pins.
  IconData get icon => switch (this) {
    roleplay => Icons.theater_comedy_outlined,
    discussion => Icons.live_help_outlined,
  };

  /// The glyph on a mid map pin; null leaves the pin state's own. A
  /// roleplay's live session has a glyph that says more (its seats, its
  /// chat), so its icon shows only while [available].
  IconData? midPinGlyph({required bool available}) => switch (this) {
    roleplay => available ? icon : null,
    discussion => icon,
  };

  /// Which card draws it on the course page and the map.
  ActivityCardStyle get cardStyle => switch (this) {
    roleplay => ActivityCardStyle.activity,
    discussion => ActivityCardStyle.discussion,
  };

  /// What a card shows once the learner has played it. A discussion has no
  /// single end, so its badge keeps counting XP up instead of stamping.
  CompletionMark get completionMark => switch (this) {
    roleplay => CompletionMark.stamp,
    discussion => CompletionMark.xpBadge,
  };

  bool get showsPlayerCount => switch (this) {
    roleplay => true,
    discussion => false,
  };

  /// Opened by joining the course's shared room for it, which the server
  /// picks: its start page offers one Join instead of the play choices, and
  /// a learner already in its room goes straight to the chat.
  bool get opensSharedRoom => switch (this) {
    roleplay => false,
    discussion => true,
  };

  /// Its sessions are offered to other learners to join (open sessions on the
  /// map and the start page).
  bool get listsOpenSessions => switch (this) {
    roleplay => true,
    discussion => false,
  };

  /// Each student ends their own seat and the room never ends as a whole:
  /// "I'm done" saves, hides and mutes the room for that student only, and
  /// the server writes the seat (synapse `discussion_room`). There is no
  /// "End for all".
  bool get endsPerSeat => switch (this) {
    roleplay => false,
    discussion => true,
  };

  /// The orchestrator suggests the learner's next line. A discussion's bot
  /// facilitates the room instead, and offers no suggestions.
  bool get offersSuggestions => switch (this) {
    roleplay => true,
    discussion => false,
  };

  /// A finished session shows the per-learner summary cards. A discussion's
  /// come with the per-learner summary every mode is getting (org
  /// activity-summary.instructions.md, "One card per learner").
  bool get showsSummary => switch (this) {
    roleplay => true,
    discussion => false,
  };

  /// A sender's name in the chat is prefixed with their role. Every student
  /// in a discussion holds the same role.
  bool get namesRoles => switch (this) {
    roleplay => true,
    discussion => false,
  };

  /// The block at the top of the chat shows a card per role.
  bool get showsRoleCards => switch (this) {
    roleplay => true,
    discussion => false,
  };

  /// That block lists the activity's questions, numbered.
  bool get listsQuestions => switch (this) {
    roleplay => false,
    discussion => true,
  };

  /// A learner arriving is announced in the timeline. A roleplay's cast is
  /// fixed when it starts; a discussion's students arrive over hours or days.
  bool get announcesArrivals => switch (this) {
    roleplay => false,
    discussion => true,
  };
}

enum ActivityCardStyle {
  /// `ActivitySuggestionCard`, with its live session state.
  activity,

  /// `DiscussionCard`.
  discussion,
}

enum CompletionMark { stamp, xpBadge }

extension ActivityPlanModeExtension on ActivityPlanModel {
  /// The mode from the plan's shape alone: for a card or a start page, where
  /// there is no session room yet.
  ActivityMode get activityMode =>
      ActivityMode.fromShape(mode: req.mode, roleIds: roles.keys);

  /// The mode a session of it in [room] plays: the room's own marker
  /// ([RoomActivityModeExtension.activityMode]) whenever there is a room, so
  /// a room made before discussions existed stays a roleplay whatever its
  /// plan says; the plan's shape only while there is none.
  ActivityMode modeIn(Room? room) => room?.activityMode ?? activityMode;
}

extension QuestActivityCardModeExtension on QuestActivityCard {
  ActivityMode get activityMode =>
      ActivityMode.fromShape(mode: mode, roleIds: roleIds);
}

extension RoomActivityModeExtension on Room {
  /// The creation-content key synapse writes on a room it made for a
  /// discussion (`{course_id, activity_id}`).
  static const String _discussionMarker = 'pangea.discussion';

  /// A room the server made for a discussion: created by the discussion bot,
  /// with the discussion marker in its creation content. Read from the create
  /// event, so it is known on the first frame, before the plan loads, and an
  /// older room whose plan happens to say "Discussion" never qualifies.
  bool get isDiscussionRoom {
    final create = getState(EventTypes.RoomCreate);
    // The marker first: every other room stops there, before the bot's name
    // is resolved from the environment.
    return create != null &&
        create.content[_discussionMarker] is Map &&
        create.senderId == BotName.byEnvironment;
  }

  /// The course a discussion room was made for, from its creation marker;
  /// null for every other room. Two courses sharing a discussion never share
  /// a room, so this is what tells a learner's room in one apart from the
  /// other.
  String? get discussionCourseId {
    if (!isDiscussionRoom) return null;
    final marker = getState(EventTypes.RoomCreate)?.content[_discussionMarker];
    final courseId = marker is Map ? marker['course_id'] : null;
    return courseId is String ? courseId : null;
  }

  /// The mode of the activity this room is a session of; null for a room
  /// that is not one. Known without the plan.
  ActivityMode? get activityMode => !isActivitySession
      ? null
      : isDiscussionRoom
      ? ActivityMode.discussion
      : ActivityMode.roleplay;
}
