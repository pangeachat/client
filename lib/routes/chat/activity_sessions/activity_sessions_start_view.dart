import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_goals_dropdown.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_participant_list.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_bottom_content.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_button_widget.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_vocab_widget.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/url_image_widget.dart';

/// The location that closes a non-embedded activity plan opened as a room/
/// session token (the chat list / a left panel): it drops ONLY that token, so
/// the rest of the workspace — notably the chat list — survives. Closing an
/// activity (e.g. one stuck on an "activity not found" error) must not also
/// clear the chat list (#7156). Returns null when no such token is open — the
/// standalone `/<activityId>` route — so the caller pops or falls back to home.
@visibleForTesting
String? activityRoomCloseLocation(Uri uri, String? roomId) {
  if (roomId == null || roomId.isEmpty) return null;
  final localpart = shortRoomId(roomId);
  bool matches(PanelToken t) =>
      (t.type == 'room' || t.type == 'session') &&
      (t.param ?? '').split('/').first == localpart;
  final panels = parseOpenPanels(uri);
  for (final t in panels.left) {
    if (matches(t)) return WorkspaceNav.closeLeft(uri, t);
  }
  for (final t in panels.right) {
    if (matches(t)) return WorkspaceNav.closeRight(uri, t);
  }
  return null;
}

class ActivitySessionStartView extends StatelessWidget {
  final ActivitySessionStartState controller;
  final ActivitySessionStateController sessionController;

  const ActivitySessionStartView(
    this.controller, {
    super.key,
    required this.sessionController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder(
      stream: Matrix.of(context).client.onRoomState.stream
          .where((update) => update.roomId == controller.widget.roomId)
          .rateLimit(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final activity = controller.activity;

        // The activity plan's close depends on whether a course is still scoped
        // (`?m=course:`) — the plan's contextual parent. Opened from the course
        // card's activity list, the scope survives (the card dropped its own
        // `left=course` but kept the filter), so the plan is the card's child and
        // its control is a back-arrow that reopens the card. Opened from a map pin,
        // the pin handler drops the scope, so the plan is parentless and its
        // control is an X that dismisses to the map. The standalone `/<activityId>`
        // route (not embedded) pops or falls back to the world map. No entry flag
        // is needed: surviving scope IS the discriminator. See
        // `routing.instructions.md`.
        final uri = GoRouter.of(context).routeInformationProvider.value.uri;
        final embedded = parseOpenPanels(
          uri,
        ).left.any((t) => t.type == 'activity');
        final courseScoped = activeSpaceIdFor(uri) != null;


        return Scaffold(
          appBar: AppBar(
            leadingWidth: 52.0,
            title: activity == null
                ? null
                : Text(
                    activity.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluffyThemes.isColumnMode(context)
                        ? theme.textTheme.titleLarge
                        : theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                  ),
            centerTitle: false,
            titleSpacing: 4,
            leading: Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Center(
                child: (embedded && courseScoped)
                    // Course still scoped → back-arrow reopens the course card.
                    ? IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => GoRouter.of(context).go(
                          WorkspaceNav.dropActivityOverlay(
                            uri,
                            reopenCourseCard: true,
                          ),
                        ),
                      )
                    : embedded
                    // Unscoped (pin entry) → X dismisses to the map.
                    ? IconButton(
                        tooltip: L10n.of(context).close,
                        icon: const Icon(Icons.close),
                        onPressed: () => GoRouter.of(
                          context,
                        ).go(WorkspaceNav.dropActivityOverlay(uri)),
                      )
                    // Opened as a room/session token (the chat list / a left
                    // panel): drop ONLY that token so the rest of the workspace
                    // — notably the chat list — survives (#7156). The standalone
                    // `/<activityId>` route has no such token: it is the bottom
                    // of the stack, so pop, or fall back to the home map.
                    : IconButton(
                        tooltip: L10n.of(context).close,
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          final close = activityRoomCloseLocation(
                            uri,
                            controller.widget.roomId,
                          );
                          if (close != null) {
                            GoRouter.of(context).go(close);
                          } else if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          } else {
                            GoRouter.of(context).go(PRoutes.world);
                          }
                        },
                      ),
              ),
            ),
            actions: [
              IconButton(
                tooltip: L10n.of(context).feedbackButton,
                icon: const Icon(Icons.flag_outlined),
                onPressed: controller.submitActivityFeedback,
              ),
            ],
          ),
          body: SafeArea(
            child: controller.loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : controller.error != null || activity == null
                ? Center(
                    child: ErrorIndicator(
                      message: L10n.of(context).activityNotFound,
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          controller: controller.scrollController,
                          child: Column(
                            children: [
                              Stack(
                                children: [
                                  // Background image — now Positioned with explicit height instead of
                                  // living inside a height-constrained Container
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    height: 375.0,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) =>
                                          ImageByUrl(
                                            imageUrl: activity.imageURL,
                                            borderRadius: BorderRadius.zero,
                                            width: constraints.maxWidth,
                                            replacement: Container(
                                              width: constraints.maxWidth,
                                              height: 350.0,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    theme
                                                        .colorScheme
                                                        .primaryContainer,
                                                    theme.colorScheme.surface,
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    top: 250.0,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.center,
                                          colors: [
                                            theme.colorScheme.surface.withAlpha(
                                              0,
                                            ),
                                            theme.colorScheme.surface,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (sessionController.showRoleCards)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 250.0,
                                      ),
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16.0,
                                          ),
                                          constraints: const BoxConstraints(
                                            maxWidth: 600.0,
                                          ),
                                          child: Opacity(
                                            opacity: sessionController
                                                .roleCardOpacity,
                                            child: ActivityParticipantList(
                                              activity: activity,
                                              room: controller.activityRoom,
                                              assignedRoles:
                                                  controller.assignedRoles,
                                              course: controller.courseParent,
                                              onTap:
                                                  sessionController.selectRole,
                                              canSelect: sessionController
                                                  .canSelectRole,
                                              isSelected: sessionController
                                                  .isRoleSelected,
                                              isShimmering: sessionController
                                                  .isRoleShimmering,
                                              showStarsCard: sessionController
                                                  .showStarsCard,
                                              completedGoalsForRole:
                                                  sessionController
                                                      .completedGoalIdsForRole,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: ActivityGoalsDropdown(
                                      goals:
                                          sessionController.selectedRoleGoals,
                                      completedGoalIds: sessionController
                                          .selectedRoleCompletedGoalIds,
                                      startCollapsed:
                                          sessionController.goalsStartCollapsed,
                                    ),
                                  ),
                                ],
                              ),
                              if (sessionController.showDescriptionSection)
                                Center(
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      maxWidth: 600.0,
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                      16.0,
                                      50.0,
                                      16.0,
                                      0.0,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      spacing: 12.0,
                                      children: [
                                        Text(
                                          activity.description,
                                          style: theme.textTheme.bodyLarge,
                                        ),
                                        if (activity.vocab.isNotEmpty)
                                          ActivityVocabWidget(
                                            key: ValueKey(
                                              'activity-start-vocab-${activity.activityId}',
                                            ),
                                            vocab: activity.vocab,
                                            langCode:
                                                activity.req.targetLanguage,
                                            targetId: 'activity-start-vocab',
                                            usedVocab: null,
                                            activityLangCode:
                                                activity.req.targetLanguage,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 600.0,
                                ),
                                padding: const EdgeInsets.all(12.0),
                                child: ActivitySessionBottomContent(
                                  sessionController,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ActivitySessionButtons(
                        controller: controller,
                        sessionController: sessionController,
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
