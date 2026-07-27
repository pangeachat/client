// ignore_for_file: implementation_imports

import 'package:flutter/material.dart';

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_goals_dropdown.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_media_carousel.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_participant_list.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_vocab_widget.dart';
import 'package:fluffychat/utils/url_launcher.dart';

class ActivitySummary extends StatelessWidget {
  final ActivityPlanModel activity;
  final Room? room;
  final Room? course;
  final Map<String, ActivityRoleModel> assignedRoles;

  final bool showInstructions;
  final VoidCallback toggleInstructions;

  final Function(String)? onTapParticipant;
  final bool Function(String)? canSelectParticipant;
  final bool Function(String)? isParticipantSelected;
  final bool Function(String)? isParticipantShimmering;
  final double Function(ActivityRoleModel?)? getParticipantOpacity;
  final bool Function(String)? showStarsCard;
  final Set<String> Function(String)? completedGoalsForRole;

  /// Opacity applied to the participant/role cards (role-selection fade).
  final double roleCardOpacity;

  /// When false, the participant/role cards are hidden.
  final bool showRoleCards;

  /// When false, the description + vocab section is hidden.
  final bool showDescriptionSection;

  /// Goals of the currently-selected role, rendered in the goals dropdown at
  /// the top of the start page. Null on the in-chat render.
  final List<ActivityRoleGoal>? goals;
  final Set<String> completedGoalIds;
  final bool goalsStartCollapsed;

  final ValueNotifier<Set<String>>? usedVocab;

  final bool inChat;

  const ActivitySummary({
    super.key,
    required this.activity,
    required this.showInstructions,
    required this.toggleInstructions,
    required this.assignedRoles,
    this.usedVocab,
    this.onTapParticipant,
    this.canSelectParticipant,
    this.isParticipantSelected,
    this.isParticipantShimmering,
    this.getParticipantOpacity,
    this.showStarsCard,
    this.completedGoalsForRole,
    this.roleCardOpacity = 1.0,
    this.showRoleCards = true,
    this.showDescriptionSection = true,
    this.goals,
    this.completedGoalIds = const {},
    this.goalsStartCollapsed = false,
    this.room,
    this.course,
    this.inChat = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Deep-link autostart: the autoplay index rides the activity token's
    // fields (route_facts.activityFor; the legacy `?autoplay=` param is
    // accepted inbound). Only the plan page (not the in-session render)
    // honors it.
    final autoplayIndex = inChat
        ? null
        : activityFor(GoRouterState.of(context))?.autoplay;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(12.0),
        constraints: const BoxConstraints(
          maxWidth: FluffyThemes.columnWidth * 1.5,
        ),
        child: Column(
          spacing: 4.0,
          children: [
            if (goals != null)
              ActivityGoalsDropdown(
                goals: goals,
                completedGoalIds: completedGoalIds,
                startCollapsed: goalsStartCollapsed,
              ),
            (!inChat ||
                    !AppConfig.useActivityImageAsChatBackground ||
                    activity.hasPlayableMedia)
                ? ActivityMediaCarousel(
                    media: activity.media,
                    fallbackImageUrl: activity.imageURL,
                    borderRadius: BorderRadius.circular(20),
                    autoplayIndex: autoplayIndex,
                  )
                : const SizedBox.shrink(),
            if (showRoleCards)
              Opacity(
                opacity: roleCardOpacity,
                child: ActivityParticipantList(
                  activity: activity,
                  room: room,
                  assignedRoles: assignedRoles,
                  course: course,
                  onTap: onTapParticipant,
                  canSelect: canSelectParticipant,
                  isSelected: isParticipantSelected,
                  isShimmering: isParticipantShimmering,
                  getOpacity: getParticipantOpacity,
                  showStarsCard: showStarsCard,
                  completedGoalsForRole: completedGoalsForRole,
                ),
              ),
            if (showDescriptionSection)
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withAlpha(180),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 16.0,
                  children: [
                    Linkify(
                      text: activity.description,
                      options: const LinkifyOptions(humanize: false),
                      useMouseRegion: true,
                      style: TextStyle(fontSize: AppConfig.messageFontSize),
                      linkStyle: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: theme.colorScheme.primary,
                      ),
                      onOpen: (link) =>
                          UrlLauncher(context, link.url).launchUrl(),
                    ),
                    const Divider(height: 1),
                    ActivityVocabWidget(
                      key: ValueKey("activity-summary-${activity.activityId}"),
                      vocab: activity.vocab,
                      langCode: activity.req.targetLanguage,
                      targetId: "activity-summary-vocab",
                      activityLangCode: activity.req.targetLanguage,
                      usedVocab: usedVocab,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
