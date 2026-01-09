import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_feedback/activity_feedback_repo.dart';
import 'package:fluffychat/pangea/activity_feedback/activity_feedback_request.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_start_page.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_summary_widget.dart';
import 'package:fluffychat/pangea/chat_settings/utils/room_summary_extension.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_dialog.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_response_dialog.dart';
import 'package:fluffychat/pangea/course_chats/open_roles_indicator.dart';
import 'package:fluffychat/pangea/course_plans/course_activities/activity_summaries_provider.dart';
import 'package:fluffychat/pangea/course_plans/course_activities/course_activity_repo.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/navigation/navigation_util.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/member_actions_popup_menu_button.dart';

class ActivitySessionStartView extends StatelessWidget {
  final ActivitySessionStartController controller;
  const ActivitySessionStartView(
    this.controller, {
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      padding: const EdgeInsets.all(8.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.0),
      ),
    );

    return StreamBuilder(
      stream: Matrix.of(context)
          .client
          .onRoomState
          .stream
          .rateLimit(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        return Scaffold(
          appBar: AppBar(
            leadingWidth: 52.0,
            title: controller.activity == null
                ? null
                : Center(
                    child: Text(
                      controller.activity!.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: !FluffyThemes.isColumnMode(context)
                          ? const TextStyle(
                              fontSize: 16,
                            )
                          : null,
                    ),
                  ),
            leading: Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.flag_outlined),
                onPressed: () async {
                  final feedback = await showDialog<String?>(
                    context: context,
                    builder: (context) {
                      return FeedbackDialog(
                        title: L10n.of(context).feedbackTitle,
                        onSubmit: (feedback) {
                          Navigator.of(context).pop(feedback);
                        },
                        scrollable: false,
                      );
                    },
                  );

                  if (feedback == null || feedback.isEmpty) {
                    return;
                  }

                  final resp = await showFutureLoadingDialog(
                    context: context,
                    future: () => ActivityFeedbackRepo.submitFeedback(
                      ActivityFeedbackRequest(
                        activityId: controller.widget.activityId,
                        feedbackText: feedback,
                        userId: Matrix.of(context).client.userID!,
                        userL1: MatrixState
                            .pangeaController.userController.userL1Code!,
                        userL2: MatrixState
                            .pangeaController.userController.userL2Code!,
                      ),
                    ),
                  );

                  if (resp.isError) {
                    return;
                  }

                  CourseActivityRepo.setSentFeedback(
                    controller.widget.activityId,
                    MatrixState.pangeaController.userController.userL1Code!,
                  );

                  await showDialog(
                    context: context,
                    builder: (context) {
                      return FeedbackResponseDialog(
                        title: L10n.of(context).feedbackTitle,
                        feedback: resp.result!.userFriendlyResponse,
                        description: L10n.of(context).feedbackRespDesc,
                      );
                    },
                  );
                },
              ),
            ],
          ),
          body: SafeArea(
            child: controller.loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : controller.error != null
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
                              child: Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 600.0,
                                ),
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  children: [
                                    ActivitySummary(
                                      activity: controller.activity!,
                                      room: controller.activityRoom,
                                      course: controller.courseParent,
                                      showInstructions:
                                          controller.showInstructions,
                                      toggleInstructions:
                                          controller.toggleInstructions,
                                      onTapParticipant: controller.selectRole,
                                      isParticipantSelected:
                                          controller.isParticipantSelected,
                                      isParticipantShimmering:
                                          controller.isParticipantShimmering,
                                      canSelectParticipant:
                                          controller.canSelectParticipant,
                                      assignedRoles: controller.assignedRoles,
                                    ),
                                    if (controller.courseParent != null &&
                                        controller.state ==
                                            SessionState.notStarted)
                                      _ActivityStatuses(
                                        statuses: controller.activityStatuses,
                                        space: controller.courseParent!,
                                        onTap: controller.joinActivityByRoomId,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          AnimatedSize(
                            duration: FluffyThemes.animationDuration,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: theme.dividerColor),
                                ),
                                color: theme.colorScheme.surface,
                              ),
                              padding: const EdgeInsets.all(24.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: FluffyThemes.maxTimelineWidth,
                                      ),
                                      child: Column(
                                        spacing: 16.0,
                                        children: [
                                          if (controller.descriptionText !=
                                              null)
                                            Text(
                                              controller.descriptionText!,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          if (controller.state ==
                                              SessionState.notStarted)
                                            _ActivityStartButtons(
                                              controller,
                                              buttonStyle,
                                            )
                                          else if (controller.state ==
                                              SessionState.confirmedRole) ...[
                                            if (controller.courseParent != null)
                                              ElevatedButton(
                                                style: buttonStyle,
                                                onPressed: controller
                                                        .canPingParticipants
                                                    ? () {
                                                        showFutureLoadingDialog(
                                                          context: context,
                                                          future: controller
                                                              .pingCourse,
                                                        );
                                                      }
                                                    : null,
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      L10n.of(context)
                                                          .pingParticipants,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if (controller
                                                .activityRoom!.isRoomAdmin) ...[
                                              if (!controller.isBotRoomMember)
                                                ElevatedButton(
                                                  style: buttonStyle,
                                                  onPressed:
                                                      controller.playWithBot,
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Text(
                                                        L10n.of(context)
                                                            .playWithBot,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ElevatedButton(
                                                style: buttonStyle,
                                                onPressed: () {
                                                  NavigationUtil.goToSpaceRoute(
                                                    controller.activityRoom!.id,
                                                    ['invite'],
                                                    context,
                                                  );
                                                },
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      L10n.of(context)
                                                          .inviteFriends,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ] else
                                            ElevatedButton(
                                              style: buttonStyle,
                                              onPressed:
                                                  controller.enableButtons
                                                      ? controller
                                                          .confirmRoleSelection
                                                      : null,
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    controller.activityRoom
                                                                ?.isRoomAdmin ??
                                                            true
                                                        ? L10n.of(context).start
                                                        : L10n.of(context)
                                                            .confirm,
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
          ),
        );
      },
    );
  }
}

class _ActivityStartButtons extends StatelessWidget {
  final ActivitySessionStartController controller;
  final ButtonStyle buttonStyle;
  const _ActivityStartButtons(
    this.controller,
    this.buttonStyle,
  );

  @override
  Widget build(BuildContext context) {
    final hasActiveSession = controller.canJoinExistingSession;
    final joinedActivityRoom = controller.joinedActivityRoomId;

    return FutureBuilder(
      future: controller.neededCourseParticipants(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }

        final int neededParticipants = snapshot.data ?? 0;
        final bool hasEnoughParticipants = neededParticipants <= 0;
        return Column(
          spacing: 16.0,
          children: [
            if (!hasEnoughParticipants) ...[
              Text(
                neededParticipants > 1
                    ? L10n.of(context).activityNeedsMembers(neededParticipants)
                    : L10n.of(context).activityNeedsOneMember,
                textAlign: TextAlign.center,
              ),
              ElevatedButton(
                style: buttonStyle,
                onPressed: controller.courseParent?.canInvite ?? false
                    ? () => context.push(
                          "/rooms/spaces/${controller.courseParent!.id}/invite",
                        )
                    : null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      L10n.of(context).inviteFriendsToCourse,
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                style: buttonStyle,
                onPressed: () => context.push(
                  "/rooms/spaces/${controller.courseParent!.id}/details?tab=course",
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      L10n.of(context).pickDifferentActivity,
                    ),
                  ],
                ),
              ),
            ] else if (joinedActivityRoom != null) ...[
              ElevatedButton(
                style: buttonStyle,
                onPressed: () {
                  NavigationUtil.goToSpaceRoute(
                    joinedActivityRoom,
                    [],
                    context,
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(L10n.of(context).continueText),
                  ],
                ),
              ),
            ] else ...[
              ElevatedButton(
                style: buttonStyle,
                onPressed: controller.startNewActivity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      hasActiveSession
                          ? L10n.of(context).startNewSession
                          : L10n.of(context).start,
                    ),
                  ],
                ),
              ),
              if (hasActiveSession)
                ElevatedButton(
                  style: buttonStyle,
                  onPressed: () async {
                    final resp = await showFutureLoadingDialog(
                      context: context,
                      future: controller.joinExistingSession,
                    );

                    if (!resp.isError) {
                      NavigationUtil.goToSpaceRoute(
                        resp.result,
                        [],
                        context,
                      );
                    }
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        L10n.of(context).joinOpenSession,
                      ),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _ActivityStatuses extends StatelessWidget {
  final Map<ActivitySummaryStatus, Map<String, RoomSummaryResponse>> statuses;
  final Room space;
  final Function(String) onTap;

  const _ActivityStatuses({
    required this.statuses,
    required this.space,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: FluffyThemes.columnWidth * 1.5,
      ),
      child: Column(
        children: [
          ...ActivitySummaryStatus.values.map(
            (status) {
              final entry = statuses[status];
              if (entry!.isEmpty) {
                return const SizedBox.shrink();
              }

              return Padding(
                padding: const EdgeInsetsGeometry.symmetric(
                  horizontal: 20.0,
                  vertical: 16.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        status.label(L10n.of(context), entry.length),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ...entry.entries.map((e) {
                      // if user is in the room, use the room info instead of the
                      // room summary response to get real-time activity roles info
                      final roomId = e.key;
                      final room =
                          Matrix.of(context).client.getRoomById(roomId);

                      final activityPlan =
                          room?.activityPlan ?? e.value.activityPlan;

                      // If activity is completed, show all roles, even for users who have left the
                      // room (like the bot). Otherwise, show only joined users with roles
                      Map<String, ActivityRoleModel> activityRoles =
                          status == ActivitySummaryStatus.completed
                              ? e.value.activityRoles.roles
                              : e.value.joinedUsersWithRoles;

                      // If the user is in the activity room and it's not completed, use the room's
                      // state events to determine roles to update them in real-time
                      if (room?.assignedRoles != null &&
                          status != ActivitySummaryStatus.completed) {
                        activityRoles = room!.assignedRoles!;
                      }

                      return ListTile(
                        title: OpenRolesIndicator(
                          roles: activityPlan.roles.values
                              .sorted((a, b) => a.id.compareTo(b.id))
                              .toList(),
                          assignedRoles: activityRoles.values.toList(),
                          size: 40.0,
                          spacing: 8.0,
                          space: space,
                          onUserTap: (user, context) {
                            showMemberActionsPopupMenu(
                              context: context,
                              user: user,
                            );
                          },
                        ),
                        trailing: space.isRoomAdmin
                            ? const Icon(Icons.arrow_forward)
                            : null,
                        onTap: space.isRoomAdmin ? () => onTap(roomId) : null,
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
