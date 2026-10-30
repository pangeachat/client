import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/archived_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/confirmed_role_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/full_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/not_started_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/select_role_session_controller.dart';
import 'package:fluffychat/routes/chat/calls/call_panel.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/layouts/cavity_controls.dart';

class ActivitySessionButtons extends StatelessWidget {
  final ActivitySessionStartState controller;
  final ActivitySessionStateController sessionController;

  /// Mobile minimized rest: render just the CTA, snug and left-aligned
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
      return _ReportsCtaHeight(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12.0, 4.0, 8.0, 12.0),
          child: _SessionCTAButtons(sessionController, compact: compact),
        ),
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
                    _SessionCTAButtons(sessionController, compact: compact),
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
/// `primary` colour when it leads, dropping to the tonal `secondaryContainer`
/// [secondary] style for any action that follows it. Public
/// because the archived fallback body renders its own leave CTA outside this
/// footer (#8064).
class ActivitySessionCTAButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  /// A de-emphasized variant for any action following the single primary: a
  /// fully filled tonal (secondaryContainer) button, mirroring the mobile CTA
  /// chips — e.g. "start my own" when joining an open session leads. Under the
  /// fidelity scheme primaryContainer is the vivid brand fill, a near twin of
  /// primary, so the quieter fill is the scheme's secondary container.
  final bool secondary;

  /// An optional leading glyph — the state CTAs pass their
  /// [ActivityPinState.icon] so the row echoes the map pins' iconography.
  final IconData? icon;

  const ActivitySessionCTAButton(
    this.text,
    this.onPressed, {
    this.secondary = false,
    this.icon,
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
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18.0),
          const SizedBox(width: 8.0),
        ],
        Flexible(child: Text(text, textAlign: TextAlign.center)),
      ],
    );
    // Mirror the mobile CTA chips' colour hierarchy: the single lead action is
    // the filled primary; every following action is a fully filled tonal
    // secondaryContainer button (not a bare outline).
    final scheme = theme.colorScheme;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: secondary ? scheme.secondaryContainer : scheme.primary,
        foregroundColor: secondary
            ? scheme.onSecondaryContainer
            : scheme.onPrimary,
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

  /// True at the minimized mobile rest — lets the not-started CTAs drop actions
  /// that don't fit (and aren't needed) in the short sheet.
  final bool compact;

  const _SessionCTAButtons(this.controller, {this.compact = false});

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
      return _NotStartedSessionCTAButtons(controller, compact: compact);
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
  final bool compact;
  const _NotStartedSessionCTAButtons(this.controller, {this.compact = false});

  @override
  Widget build(BuildContext context) {
    // Other sub-pages show a single Back button.
    if (controller.subPage != NotStartedSubPage.main) {
      return ActivitySessionCTAButton(
        L10n.of(context).back,
        controller.goBackFromSubPage,
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
        // invite / pick-different actions.
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
              // Only when the sheet is roomy (maximized / web). It just leaves
              // the activity — unnecessary in the minimized map view, and it
              // wouldn't fit the short rest. Maximized it returns to the course
              // card, or closes back to the map. Primary only when it leads;
              // with invite above it, it drops to the lighter secondary.
              if (!compact)
                ActivitySessionCTAButton(
                  L10n.of(context).pickDifferentActivity,
                  controller.goToCourse,
                  secondary: controller.canInviteToCourse,
                ),
            ],
          );
        }

        // The browse CTA: the same vertical layout at every size. An action
        // from the minimized phone sheet maximizes it first, since the view it
        // opens (role picker, Completed) is dropped at the minimized rest;
        // Continue is exempt, as it leaves for the chat.
        final expand = CavityControls.maybeExpandToFull(context);
        VoidCallback expandThen(VoidCallback action) => () {
          expand?.call();
          action();
        };

        return Column(
          spacing: 16.0,
          children: [
            if (controller.joinedActivityRoomId != null) ...[
              ActivitySessionCTAButton(
                L10n.of(context).continueText,
                controller.goToJoinedActivity,
                icon: ActivityPinState.ongoingActive.icon,
              ),
            ] else ...[
              // An open session to join is the encouraged choice, so it leads
              // and "start my own" drops to a de-emphasized option; with none to
              // join, starting is the single primary action.
              if (controller.offersBot)
                _PlayChoiceTiles(
                  playWithBot: expandThen(controller.playWithBot),
                  playWithOthers: expandThen(controller.playWithHuman),
                )
              // A larger activity's single button joins a waiting session when
              // there is one, so it says so; otherwise it starts a new one.
              else if (controller.openSessionCount > 0)
                ActivitySessionCTAButton(
                  L10n.of(context).joinOpenSession,
                  expandThen(controller.playWithHuman),
                  icon: ActivityPinState.joinable.icon,
                )
              else
                ActivitySessionCTAButton(
                  L10n.of(context).start,
                  expandThen(controller.playWithHuman),
                  icon: ActivityPinState.available.icon,
                ),
            ],
            // Completed sits below the start/join choice, de-emphasized, for any
            // viewer with sessions to review (see [hasCompletedSessions]).
            if (controller.hasCompletedSessions)
              ActivitySessionCTAButton(
                L10n.of(context).mapFilterCompleted,
                expandThen(controller.goToViewPage),
                secondary: true,
                icon: ActivityPinState.inProgress.icon,
              ),
          ],
        );
      },
    );
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
    return ActivitySessionCTAButton(L10n.of(context).leave, page.leaveSession);
  }
}

class _ConfirmedRoleSessionCTAButtons extends StatelessWidget {
  final ConfirmedRoleSessionController controller;
  const _ConfirmedRoleSessionCTAButtons(this.controller);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    if (controller.sessionStarted) {
      return ActivitySessionCTAButton(
        l10n.continueText,
        controller.continueToChat,
        icon: ActivityPinState.ongoingActive.icon,
      );
    }
    // Bringing people in leads; the bot is the quieter fallback at the bottom.
    return Column(
      mainAxisSize: .min,
      spacing: 16.0,
      children: [
        _WaitingStatusLine(controller),
        if (controller.showInviteOptions)
          ActivitySessionCTAButton(
            l10n.inviteFriends,
            controller.inviteFriends,
          ),
        if (controller.showPingCourse)
          FutureBuilder(
            future: controller.canPingParticipants,
            builder: (context, snapshot) => ActivitySessionCTAButton(
              l10n.pingParticipants,
              snapshot.data == true ? controller.pingCourse : null,
            ),
          ),
        if (controller.showInviteOptions)
          ActivitySessionCTAButton(
            l10n.playWithBot,
            controller.enablePlayWithBot ? controller.playWithBot : null,
            secondary: true,
          ),
      ],
    );
  }
}

/// "Play with Pangea Bot" and "Play with others" as two equal, tall tiles —
/// a two-seat activity's main choice at every size. Playing with others sits
/// on the right, the easier reach for a right thumb. The glyph sits above the
/// label, so the label has the tile's whole width to wrap in on a narrow
/// phone, where the tile is a little smaller than on web (still room for a
/// two-line label under the glyph).
class _PlayChoiceTiles extends StatelessWidget {
  final VoidCallback playWithBot;
  final VoidCallback playWithOthers;

  const _PlayChoiceTiles({
    required this.playWithBot,
    required this.playWithOthers,
  });

  /// The least a tile takes; it grows (both tiles together) when a label
  /// wraps onto a second line under the glyph.
  static const double _minHeight = 88.0;
  static const double _phoneMinHeight = 84.0;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wide = FluffyThemes.isColumnMode(context);
    // Both glyphs sit in the same height of slot, so the two labels line up.
    final glyphSlot = wide ? 32.0 : 28.0;
    final style = ElevatedButton.styleFrom(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      padding: wide
          ? const EdgeInsets.all(12.0)
          : const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
    );
    final choices = [
      (
        l10n.playWithBot,
        _BotAvatarGlyph(size: wide ? 40.0 : 36.0, slot: glyphSlot) as Widget,
        playWithBot,
      ),
      (
        l10n.playWithOthers,
        SizedBox(
              height: glyphSlot,
              child: Icon(Icons.group_outlined, size: wide ? 28.0 : 24.0),
            )
            as Widget,
        playWithOthers,
      ),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12.0,
        children: [
          for (final (label, glyph, action) in choices)
            Expanded(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: wide ? _minHeight : _phoneMinHeight,
                ),
                child: ElevatedButton(
                  style: style,
                  onPressed: action,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: wide ? 6.0 : 4.0,
                    children: [
                      glyph,
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The Pangea Bot's face on a filled `primary` tile, with no avatar circle: at
/// tile size his silhouette is what reads as him. He stays brand purple, in
/// the opposite shade to the tile (`inversePrimary`: light on light mode's dark
/// tile, dark on dark mode's light one), so he never melts into the button.
class _BotAvatarGlyph extends StatelessWidget {
  final double size;

  /// The height he takes in the tile. His animation has empty space around
  /// him, which spills past this (unclipped) so he can be drawn at [size]
  /// while the label under him lines up with the next tile's.
  final double slot;

  const _BotAvatarGlyph({required this.size, required this.slot});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: slot,
    child: OverflowBox(
      minHeight: size,
      maxHeight: size,
      child: BotFace(
        width: size,
        expression: BotExpression.idle,
        forceColor: Theme.of(context).colorScheme.inversePrimary,
        // He sits in a button, so he appears in place rather than dropping
        // in.
        playEntrance: false,
      ),
    ),
  );
}

/// Tells the shell how tall the minimized sheet's CTA area is on a phone
/// ([ActivitySheetCtaHeight]), so the sheet grows to fit buttons that stack or
/// wrap. It reports after every layout rather than every build: the buttons
/// arrive in a FutureBuilder below it, which rebuilds without rebuilding this.
class _ReportsCtaHeight extends SingleChildRenderObjectWidget {
  const _ReportsCtaHeight({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReportsCtaHeight(reports: !FluffyThemes.isColumnMode(context));

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReportsCtaHeight renderObject,
  ) => renderObject.reports = !FluffyThemes.isColumnMode(context);
}

class _RenderReportsCtaHeight extends RenderProxyBox {
  _RenderReportsCtaHeight({required this.reports});

  bool reports;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    // The loading bar is shorter than any real set of buttons. Reporting it
    // would shrink the sheet, and the resize rebuilds the page, which starts
    // the participant check (and the bar) over — so it is never reported.
    if (height < ActivitySheetCtaHeight.defaultHeight) return;
    if (!reports || height == _reported) return;
    _reported = height;
    // The shell rebuilds on it, which can't happen mid-layout.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ActivitySheetCtaHeight.set(height),
    );
  }
}

/// The waiting room's status line: how long until Pangea Bot takes the open
/// seat, or else how long this session has waited, and how many coursemates
/// are online right now.
class _WaitingStatusLine extends StatelessWidget {
  final ConfirmedRoleSessionController controller;

  const _WaitingStatusLine(this.controller);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16.0,
      runSpacing: 8.0,
      children: [
        ValueListenableBuilder(
          valueListenable: controller.clock,
          builder: (context, now, _) {
            final botJoinsAt = controller.botJoinsAt;
            final since = controller.waitingSince;
            final IconData icon;
            final String text;
            if (botJoinsAt != null) {
              // The bot's sweep runs every few minutes, so it can join a
              // little after the hour.
              final left = botJoinsAt.difference(now);
              icon = Icons.smart_toy_outlined;
              text = left > Duration.zero
                  ? l10n.botJoinsIn(formatCallDuration(left))
                  : l10n.botIsJoining;
            } else if (since != null) {
              icon = Icons.schedule;
              text = l10n.waitingFor(formatCallDuration(now.difference(since)));
            } else {
              return const SizedBox.shrink();
            }
            return Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4.0,
              children: [
                Icon(icon, size: 16.0, color: style?.color),
                Text(text, style: style),
              ],
            );
          },
        ),
        ListenableBuilder(
          listenable: Listenable.merge([
            controller.coursemateIds,
            controller.presence,
          ]),
          builder: (context, _) {
            if (controller.coursemateIds.value == null) {
              return const SizedBox.shrink();
            }
            final count = controller.onlineCoursemateCount;
            return Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6.0,
              children: [
                Icon(
                  Icons.circle,
                  size: 10.0,
                  color: count > 0
                      ? theme.pangea.success
                      : theme.colorScheme.outline,
                ),
                Flexible(
                  child: Text(
                    l10n.onlineInCourse(
                      count,
                      controller.course?.getLocalizedDisplayname(
                            MatrixLocals(l10n),
                          ) ??
                          '',
                    ),
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
