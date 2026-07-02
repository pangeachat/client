import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/confirmed_role_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/full_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/not_started_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/select_role_session_controller.dart';

class ActivitySessionButtons extends StatelessWidget {
  final ActivitySessionStartState controller;
  final ActivitySessionStateController sessionController;

  const ActivitySessionButtons({
    super.key,
    required this.controller,
    required this.sessionController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = sessionController.descriptionText;

    return AnimatedSize(
      alignment: Alignment.bottomCenter,
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
                    if (description != null)
                      Semantics(
                        label: description,
                        enabled: false,
                        child: Text(
                          description,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    _SessionCTAButtons(sessionController),
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

class _CTAButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  const _CTAButton(this.text, this.onPressed);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colorScheme.primaryContainer,
        foregroundColor: theme.colorScheme.onPrimaryContainer,
        padding: const EdgeInsets.all(8.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
        ),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Flexible(child: Text(text, textAlign: TextAlign.center))],
      ),
    );
  }
}

class _SessionCTAButtons extends StatelessWidget {
  final ActivitySessionStateController controller;

  const _SessionCTAButtons(this.controller);

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;

    if (controller is SelectRoleSessionController) {
      return _SelectRoleSessionCTAButtons(controller);
    }

    if (controller is FullSessionController) {
      return _FullSessionCTAButtons(controller);
    }

    if (controller is NotStartedSessionController) {
      return _NotStartedSessionCTAButtons(controller);
    }

    if (controller is ConfirmedRoleSessionController) {
      return _ConfirmedRoleSessionCTAButtons(controller);
    }

    return SizedBox();
  }
}

class _SelectRoleSessionCTAButtons extends StatelessWidget {
  final SelectRoleSessionController controller;
  const _SelectRoleSessionCTAButtons(this.controller);

  @override
  Widget build(BuildContext context) {
    return _CTAButton(
      L10n.of(context).confirm,
      controller.canConfirmRole ? controller.confirmRoleSelection : null,
    );
  }
}

class _FullSessionCTAButtons extends StatelessWidget {
  final FullSessionController controller;
  const _FullSessionCTAButtons(this.controller);

  @override
  Widget build(BuildContext context) {
    return _CTAButton(
      controller.course != null
          ? L10n.of(context).returnToCourse
          : L10n.of(context).returnHome,
      controller.returnFromFullSession,
    );
  }
}

class _NotStartedSessionCTAButtons extends StatelessWidget {
  final NotStartedSessionController controller;
  const _NotStartedSessionCTAButtons(this.controller);

  @override
  Widget build(BuildContext context) {
    // Sub-pages show a single Back button.
    if (controller.subPage != NotStartedSubPage.main) {
      return _CTAButton(L10n.of(context).back, controller.goToMainPage);
    }

    return FutureBuilder(
      future: controller.neededCourseParticipants,
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
              _CTAButton(
                L10n.of(context).inviteFriendsToCourse,
                controller.inviteToCourse,
              ),
              _CTAButton(
                L10n.of(context).pickDifferentActivity,
                controller.goToCourse,
              ),
            ] else if (controller.joinedActivityRoomId != null) ...[
              _CTAButton(
                L10n.of(context).continueText,
                controller.goToJoinedActivity,
              ),
            ] else ...[
              _CTAButton(L10n.of(context).start, controller.startNewActivity),
              if (controller.openSessionCount > 0)
                _CTAButton(
                  '${L10n.of(context).joinOpenSession} (${controller.openSessionCount})',
                  controller.goToJoinPage,
                ),
              if (controller.course?.isRoomAdmin == true &&
                  controller.hasCurrentOrFinishedSessions)
                _CTAButton(
                  '${L10n.of(context).viewCurrentOrFinished} (${controller.currentOrFinishedSessionCount})',
                  controller.goToViewPage,
                ),
            ],
          ],
        );
      },
    );
  }
}

class _ConfirmedRoleSessionCTAButtons extends StatelessWidget {
  final ConfirmedRoleSessionController controller;
  const _ConfirmedRoleSessionCTAButtons(this.controller);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      children: [
        if (controller.showPingCourse) ...[
          FutureBuilder(
            future: controller.canPingParticipants,
            builder: (context, snapshot) => _CTAButton(
              L10n.of(context).pingParticipants,
              snapshot.data == true ? controller.pingCourse : null,
            ),
          ),
          SizedBox(height: 16.0),
        ],
        if (controller.showInviteOptions)
          Padding(
            padding: EdgeInsetsGeometry.only(bottom: 16.0),
            child: _CTAButton(
              L10n.of(context).playWithBot,
              controller.enablePlayWithBot ? controller.playWithBot : null,
            ),
          ),
        if (controller.showInviteOptions)
          _CTAButton(L10n.of(context).inviteFriends, controller.inviteFriends),
      ],
    );
  }
}
