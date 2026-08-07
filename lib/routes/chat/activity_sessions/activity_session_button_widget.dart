import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/archived_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/confirmed_role_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/full_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/not_started_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/select_role_session_controller.dart';
import 'package:fluffychat/widgets/layouts/cavity_controls.dart';

class ActivitySessionButtons extends StatelessWidget {
  final ActivitySessionStartState controller;
  final ActivitySessionStateController sessionController;

  /// Mobile minimized rest: render just the CTA row, snug and left-aligned
  /// under the info row (no divider, description, centering, or heavy padding),
  /// so the minimized sheet reads as densely as the course card's compact peek.
  final bool compact;

  const ActivitySessionButtons({
    super.key,
    required this.controller,
    required this.sessionController,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = sessionController.descriptionText;

    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12.0, 4.0, 8.0, 12.0),
        child: _SessionCTAButtons(sessionController),
      );
    }

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

/// The session page's call-to-action button: a full-width filled button in the
/// primary container colour. Public because the archived fallback body renders
/// its own leave CTA outside this footer (#8064).
class ActivitySessionCTAButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  /// A de-emphasized variant for any action following the single primary: a
  /// fully filled but lighter (primaryContainer) button, mirroring the mobile
  /// CTA chips — e.g. "start my own" when joining an open session leads.
  final bool secondary;

  const ActivitySessionCTAButton(
    this.text,
    this.onPressed, {
    this.secondary = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20.0),
    );
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [Flexible(child: Text(text, textAlign: TextAlign.center))],
    );
    // Mirror the mobile CTA chips' colour hierarchy: the single lead action is
    // the darker filled primary; every following action is a fully filled but
    // lighter primaryContainer button (not a bare outline).
    final scheme = theme.colorScheme;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: secondary ? scheme.primaryContainer : scheme.primary,
        foregroundColor: secondary ? scheme.onPrimaryContainer : scheme.onPrimary,
        padding: const EdgeInsets.all(8.0),
        shape: shape,
      ),
      onPressed: onPressed,
      child: child,
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

    if (controller is ArchivedSessionController) {
      return _ArchivedSessionCTAButtons(controller);
    }

    return SizedBox();
  }
}

class _SelectRoleSessionCTAButtons extends StatelessWidget {
  final SelectRoleSessionController controller;
  const _SelectRoleSessionCTAButtons(this.controller);

  @override
  Widget build(BuildContext context) {
    return ActivitySessionCTAButton(
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
    return ActivitySessionCTAButton(
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
      return ActivitySessionCTAButton(
        L10n.of(context).back,
        controller.goToMainPage,
      );
    }

    return FutureBuilder(
      future: controller.neededCourseParticipants,
      builder: (context, snapshot) {
        // Wait on the participant count AND the open-session summaries, so the
        // join/start choice never flashes "Start" before the sessions land.
        if (snapshot.connectionState == ConnectionState.waiting ||
            controller.summariesLoading) {
          return const LinearProgressIndicator();
        }

        final int neededParticipants = snapshot.data ?? 0;
        final bool hasEnoughParticipants = neededParticipants <= 0;

        // Not enough course participants yet — a blocking notice with its own
        // invite / pick-different actions. Stays a vertical list on both
        // platforms (it isn't the browse CTA the horizontal row replaces).
        if (!hasEnoughParticipants) {
          return Column(
            spacing: 16.0,
            children: [
              Text(
                neededParticipants > 1
                    ? L10n.of(context).activityNeedsMembers(neededParticipants)
                    : L10n.of(context).activityNeedsOneMember,
                textAlign: TextAlign.center,
              ),
              // Only for learners who can actually invite — without the power
              // level the invite page just errors out (#7875).
              if (controller.canInviteToCourse)
                ActivitySessionCTAButton(
                  L10n.of(context).inviteFriendsToCourse,
                  controller.inviteToCourse,
                ),
              // Primary only when it leads — with invite above it, it drops to
              // the lighter secondary so a single darker CTA stays on top.
              ActivitySessionCTAButton(
                L10n.of(context).pickDifferentActivity,
                controller.goToCourse,
                secondary: controller.canInviteToCourse,
              ),
            ],
          );
        }

        // The browse CTA: the horizontal row on mobile, the vertical layout
        // below on web.
        if (!FluffyThemes.isColumnMode(context)) {
          return _NotStartedMobileCtaRow(controller);
        }

        return Column(
          spacing: 16.0,
          children: [
            if (controller.joinedActivityRoomId != null) ...[
              ActivitySessionCTAButton(
                L10n.of(context).continueText,
                controller.goToJoinedActivity,
              ),
            ] else ...[
              // An open session to join is the encouraged choice, so it leads
              // and "start my own" drops to a de-emphasized option; with none to
              // join, starting is the single primary action.
              if (controller.openSessionCount > 0) ...[
                ActivitySessionCTAButton(
                  '${L10n.of(context).joinOpenSession} (${controller.openSessionCount})',
                  controller.goToJoinPage,
                ),
                ActivitySessionCTAButton(
                  L10n.of(context).startOwn,
                  controller.startNewActivity,
                  secondary: true,
                ),
              ] else
                ActivitySessionCTAButton(
                  L10n.of(context).start,
                  controller.startNewActivity,
                ),
            ],
            // Completed sits below the start/join choice for any learner with
            // finished sessions to review (an admin sees all; everyone else
            // sees their own), de-emphasized like the mobile chip.
            if (controller.hasCompletedSessions)
              ActivitySessionCTAButton(
                L10n.of(context).mapFilterCompleted,
                controller.goToViewPage,
                secondary: true,
              ),
          ],
        );
      },
    );
  }
}

/// The mobile browse-step CTA: a single horizontally scrolling row. Exactly one
/// filled primary leads (Ongoing → Join → Start), followed by any other
/// available actions, with the everyone-visible Completed chip and then share +
/// flag always appended last as light pills. The later steps (role picker,
/// waiting room) keep their vertical lists. See
/// activity-start-page.instructions.md.
class _NotStartedMobileCtaRow extends StatelessWidget {
  final NotStartedSessionController controller;
  const _NotStartedMobileCtaRow(this.controller);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final page = controller.widget.controller;
    final chips = <Widget>[];

    // An action chip maximizes the sheet before running — the view it opens
    // (role picker, sessions list) is dropped by the minimized LayoutBuilder,
    // so it must reach full first. Continue is exempt: it leaves for the chat.
    final expand = CavityControls.maybeExpandToFull(context);
    VoidCallback expandThen(VoidCallback action) => () {
      expand?.call();
      action();
    };

    if (controller.joinedActivityRoomId != null) {
      chips.add(
        _ActivityCtaChip(
          label: l10n.continueText,
          onPressed: controller.goToJoinedActivity,
          filled: true,
        ),
      );
    } else if (controller.openSessionCount > 0) {
      chips.add(
        _ActivityCtaChip(
          label: '${l10n.joinOpenSession} (${controller.openSessionCount})',
          onPressed: expandThen(controller.goToJoinPage),
          filled: true,
        ),
      );
      chips.add(
        _ActivityCtaChip(
          label: l10n.startOwn,
          onPressed: expandThen(controller.startNewActivity),
        ),
      );
    } else {
      chips.add(
        _ActivityCtaChip(
          label: l10n.start,
          onPressed: expandThen(controller.startNewActivity),
          filled: true,
        ),
      );
    }

    // Opens the Completed subpage — the learner's own finished sessions, or all
    // of them (their own first) for a course admin.
    if (controller.hasCompletedSessions) {
      chips.add(
        _ActivityCtaChip(
          label: l10n.mapFilterCompleted,
          onPressed: expandThen(controller.goToViewPage),
        ),
      );
    }

    chips.add(
      _ActivityCtaChip(
        icon: Icons.share_outlined,
        tooltip: l10n.share,
        onPressed: page.copyActivityLink,
      ),
    );
    chips.add(
      _ActivityCtaChip(
        icon: Icons.flag_outlined,
        tooltip: l10n.feedbackButton,
        onPressed: page.submitActivityFeedback,
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(spacing: 8.0, children: chips),
    );
  }
}

/// A pill in the mobile CTA row. The single primary action is [filled] (solid
/// primary); every other action — including share and flag — is a light
/// primaryContainer pill. Passing [icon] with no [label] renders a circular
/// icon-only chip (share / flag) sized to match the text pills' height.
class _ActivityCtaChip extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool filled;
  final String? tooltip;

  const _ActivityCtaChip({
    this.label,
    this.icon,
    required this.onPressed,
    this.filled = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = ElevatedButton.styleFrom(
      backgroundColor: filled
          ? theme.colorScheme.primary
          : theme.colorScheme.primaryContainer,
      foregroundColor: filled
          ? theme.colorScheme.onPrimary
          : theme.colorScheme.onPrimaryContainer,
      elevation: 0.0,
      shape: const StadiumBorder(),
    );

    final Widget button = icon != null && label == null
        ? SizedBox(
            height: 40.0,
            width: 40.0,
            child: ElevatedButton(
              style: style.copyWith(
                padding: WidgetStateProperty.all(EdgeInsets.zero),
                shape: WidgetStateProperty.all(const CircleBorder()),
              ),
              onPressed: onPressed,
              child: Icon(icon, size: 20.0),
            ),
          )
        : SizedBox(
            height: 40.0,
            child: ElevatedButton(
              style: style.copyWith(
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 20.0),
                ),
              ),
              onPressed: onPressed,
              child: Text(label ?? ''),
            ),
          );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// A removed activity's session can't be continued or finished and no one else
/// can be invited into it, so the only action left in the footer is getting it
/// out of the chat list (#8064).
class _ArchivedSessionCTAButtons extends StatelessWidget {
  final ArchivedSessionController controller;
  const _ArchivedSessionCTAButtons(this.controller);

  @override
  Widget build(BuildContext context) {
    final page = controller.widget.controller;
    if (!page.canLeaveArchivedSession) return const SizedBox.shrink();
    return ActivitySessionCTAButton(
      L10n.of(context).leave,
      page.leaveArchivedSession,
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
        // Ping, play with bot, and invite friends are all equally valid ways
        // forward from the waiting room, so none is emphasized — every one is
        // the lighter secondary.
        if (controller.showPingCourse) ...[
          FutureBuilder(
            future: controller.canPingParticipants,
            builder: (context, snapshot) => ActivitySessionCTAButton(
              L10n.of(context).pingParticipants,
              snapshot.data == true ? controller.pingCourse : null,
              secondary: true,
            ),
          ),
          SizedBox(height: 16.0),
        ],
        if (controller.showInviteOptions)
          Padding(
            padding: EdgeInsetsGeometry.only(bottom: 16.0),
            child: ActivitySessionCTAButton(
              L10n.of(context).playWithBot,
              controller.enablePlayWithBot ? controller.playWithBot : null,
              secondary: true,
            ),
          ),
        if (controller.showInviteOptions)
          ActivitySessionCTAButton(
            L10n.of(context).inviteFriends,
            controller.inviteFriends,
            secondary: true,
          ),
      ],
    );
  }
}
