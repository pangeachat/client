import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_start_page.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/navigation/navigation_util.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class ActivitySessionButtonWidget extends StatelessWidget {
  final ActivitySessionStartController controller;

  const ActivitySessionButtonWidget({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      padding: const EdgeInsets.all(8.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
    );

    return AnimatedSize(
      duration: FluffyThemes.animationDuration,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor)),
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
                    if (controller.descriptionText != null)
                      Text(
                        controller.descriptionText!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    switch (controller.state) {
                      SessionState.notStarted => _ActivityStartButtons(
                        controller,
                        buttonStyle,
                      ),
                      SessionState.confirmedRole =>
                        _ActivityRoleConfirmedButtons(
                          buttonStyle: buttonStyle,
                          controller: controller,
                        ),
                      _ => ElevatedButton(
                        style: buttonStyle,
                        onPressed: controller.confirmRoleSelection,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              controller.activityRoom?.isRoomAdmin ?? true
                                  ? L10n.of(context).start
                                  : L10n.of(context).confirm,
                            ),
                          ],
                        ),
                      ),
                    },
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityStartButtons extends StatelessWidget {
  final ActivitySessionStartController controller;
  final ButtonStyle buttonStyle;
  const _ActivityStartButtons(this.controller, this.buttonStyle);

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
                  children: [Text(L10n.of(context).inviteFriendsToCourse)],
                ),
              ),
              ElevatedButton(
                style: buttonStyle,
                onPressed: () => context.push(
                  "/rooms/spaces/${controller.courseParent!.id}/details?tab=course",
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [Text(L10n.of(context).pickDifferentActivity)],
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
                  children: [Text(L10n.of(context).continueText)],
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
                      NavigationUtil.goToSpaceRoute(resp.result, [], context);
                    }
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [Text(L10n.of(context).joinOpenSession)],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _ActivityRoleConfirmedButtons extends StatelessWidget {
  final ButtonStyle buttonStyle;
  final ActivitySessionStartController controller;

  const _ActivityRoleConfirmedButtons({
    required this.buttonStyle,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      children: [
        if (controller.courseParent != null)
          ElevatedButton(
            style: buttonStyle,
            onPressed: controller.canPingParticipants
                ? () {
                    showFutureLoadingDialog(
                      context: context,
                      future: controller.pingCourse,
                    );
                  }
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    L10n.of(context).pingParticipants,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        if (controller.activityRoom!.isRoomAdmin) ...[
          if (!controller.isBotRoomMember)
            ElevatedButton(
              style: buttonStyle,
              onPressed: controller.playWithBot,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [Text(L10n.of(context).playWithBot)],
              ),
            ),
          ElevatedButton(
            style: buttonStyle,
            onPressed: () {
              NavigationUtil.goToSpaceRoute(controller.activityRoom!.id, [
                'invite',
              ], context);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Text(L10n.of(context).inviteFriends)],
            ),
          ),
        ],
      ],
    );
  }
}
