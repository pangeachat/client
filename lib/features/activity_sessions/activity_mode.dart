import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The activity modes, and every way a mode changes how its activities look
/// and run (#9647). Screens ask the mode a question ("does it name roles?")
/// rather than checking for one mode, so a new mode is added here: give it a
/// value, and the exhaustive switches below name every answer it needs.
enum ActivityMode {
  /// Players take roles and work toward their own goals. Every mode without
  /// an experience of its own yet (Debate, Decision Making, 20 Questions,
  /// Conversation) plays as a roleplay.
  roleplay,

  /// A course's shared room of students talking about one photo and a few
  /// questions, with the bot facilitating (org discussions doc).
  discussion;

  /// The mode a plan's `mode` field names.
  static ActivityMode fromPlanMode(String? mode) =>
      mode?.toLowerCase() == 'discussion' ? discussion : roleplay;

  /// The tag on its cards.
  String label(L10n l10n) => switch (this) {
    roleplay => l10n.roleplayLabel,
    discussion => l10n.discussionLabel,
  };

  /// The icon beside that tag, and the glyph on its map pins.
  IconData get icon => switch (this) {
    roleplay => Icons.theater_comedy_outlined,
    discussion => Icons.live_help_outlined,
  };

  /// The glyph on its map pins; null for none.
  IconData? get pinGlyph => switch (this) {
    roleplay => null,
    discussion => icon,
  };

  /// What a card shows once the learner has played it: the completed stamp,
  /// or a gold badge with the XP earned there, which keeps counting up since
  /// a discussion has no single end.
  CompletionMark get completionMark => switch (this) {
    roleplay => CompletionMark.stamp,
    discussion => CompletionMark.xpBadge,
  };

  /// A card shows how many players the activity takes. A discussion has no
  /// set number.
  bool get showsPlayerCount => switch (this) {
    roleplay => true,
    discussion => false,
  };

  /// Opened by joining the course's shared room for it, picked by the server,
  /// rather than through the activity's start page.
  bool get opensSharedRoom => switch (this) {
    roleplay => false,
    discussion => true,
  };

  /// In the chat, a sender's name is prefixed with their role. Every student
  /// in a discussion holds the same role, so there it says nothing.
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

  /// What sits at the top of the chat.
  ActivityHeader get header => switch (this) {
    roleplay => ActivityHeader.goalMenu,
    discussion => ActivityHeader.questions,
  };
}

/// What an activity's card shows once the learner has played it.
enum CompletionMark { stamp, xpBadge }

/// The header at the top of an activity's chat.
enum ActivityHeader {
  /// The roleplay goal menu (`ActivityStatsMenu`).
  goalMenu,

  /// The current question and the question circles
  /// (`DiscussionQuestionHeader`).
  questions,
}

extension ActivityPlanModeExtension on ActivityPlanModel {
  ActivityMode get activityMode => ActivityMode.fromPlanMode(req.mode);
}

extension QuestActivityCardModeExtension on QuestActivityCard {
  ActivityMode get activityMode => ActivityMode.fromPlanMode(mode);
}

extension RoomActivityModeExtension on Room {
  /// The mode of the activity this room is a session of; null for a room
  /// that is not one, and until its plan has loaded (rebuild on
  /// `ActivityPlanRepo` to see it arrive).
  ActivityMode? get activityMode =>
      isActivitySession ? activityPlan?.activityMode : null;
}
