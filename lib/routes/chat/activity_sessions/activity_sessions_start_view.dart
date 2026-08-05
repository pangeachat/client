import 'package:flutter/material.dart';

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/languages/language_flag_chip.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/room_close_location.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_rating_meter.dart';
import 'package:fluffychat/routes/home/pangea_logo_svg.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_bottom_content.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_button_widget.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_start_hero.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_vocab_widget.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

// The close-only-this-room-token location moved to the navigation layer
// (`roomTokenCloseLocation`) once leaving a chat needed the same semantic
// (#7561); the activity plan's close (#7156) reads it from there.

/// Below this body height the start page is at its mobile minimized rest and
/// renders only the header + info row + CTA — the scroll content is dropped
/// until the sheet is dragged/tapped up. Kept in step with
/// `_activitySheetMinimizedHeight` in workspace_shell.dart, the cavity height
/// that produces this. See activity-start-page.instructions.md.
const double kActivityCompactMaxHeight = 150.0;

class ActivitySessionStartView extends StatelessWidget {
  final ActivitySessionStartState controller;
  final ActivitySessionStateController sessionController;

  const ActivitySessionStartView(
    this.controller, {
    super.key,
    required this.sessionController,
  });

  String? _archivedRoomName(BuildContext context) {
    if (!controller.isArchived) return null;
    return controller.activityRoom?.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
  }

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
        ).left.any((t) => t.type == PanelTypesEnum.activity);
        final courseScoped = activeSpaceIdFor(uri) != null;

        return Scaffold(
          appBar: AppBar(
            leadingWidth: 52.0,
            // With no plan, an archived session falls back to the room name —
            // it was set from the plan's title at room creation.
            title: (activity?.title ?? _archivedRoomName(context)) == null
                ? null
                : Text(
                    activity?.title ?? _archivedRoomName(context)!,
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
                          final close = roomTokenCloseLocation(
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
              // The one camera path that zooms (#7616): selection only pans,
              // so this button zoom+pans the map to the activity's pin.
              IconButton(
                tooltip: L10n.of(context).focusOnMap,
                icon: const Icon(Icons.filter_center_focus),
                onPressed: MapCameraFocusRequests.request,
              ),
            ],
          ),
          body: controller.loading
              ? const Center(child: CircularProgressIndicator.adaptive())
              // Transient fetch failure — retryable, never the archived view
              // or the "no longer supported" notice (the fallback ladder in
              // activities.instructions.md engages only on a confirmed 404).
              : controller.error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: ErrorIndicator(
                      message: L10n.of(context).activityLoadFailed,
                    ),
                  ),
                )
              // Confirmed removed, with a session and no plan recoverable from
              // its room state: archived body from role/goal state alone.
              // Without a session there is nothing to build it from, so a
              // removed activity falls through to not-found (#7918).
              : activity == null && controller.isArchived
              ? _ArchivedSessionFallbackBody(controller)
              : activity == null
              ? Center(
                  child: ErrorIndicator(
                    message: L10n.of(context).activityNotFound,
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxHeight.isFinite &&
                        constraints.maxHeight < kActivityCompactMaxHeight;
                    // Snug: no scroll content, so no Expanded — the CTA sits
                    // directly under the info row (mirrors the course card's
                    // compact peek).
                    if (compact) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ActivityStartInfoRow(activity: activity),
                          ActivitySessionButtons(
                            controller: controller,
                            sessionController: sessionController,
                            compact: true,
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        _ActivityStartInfoRow(activity: activity),
                        // Web keeps the vertical CTA at the bottom; share and flag
                        // sit here as de-emphasized buttons instead. On mobile they
                        // are chips in the bottom CTA row.
                        if (FluffyThemes.isColumnMode(context))
                          _ActivityStartShareFlagRow(controller),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: controller.scrollController,
                            child: Column(
                              children: [
                                ActivityStartHero(
                                  controller: controller,
                                  sessionController: sessionController,
                                  activity: activity,
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
                                          Linkify(
                                            text: activity.description,
                                            options: const LinkifyOptions(
                                              humanize: false,
                                            ),
                                            useMouseRegion: true,
                                            style: theme.textTheme.bodyLarge,
                                            linkStyle: theme.textTheme.bodyLarge
                                                ?.copyWith(
                                                  color:
                                                      theme.colorScheme.primary,
                                                  decoration:
                                                      TextDecoration.underline,
                                                  decorationColor:
                                                      theme.colorScheme.primary,
                                                ),
                                            onOpen: (link) => UrlLauncher(
                                              context,
                                              link.url,
                                            ).launchUrl(),
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
                    );
                  },
                ),
        );
      },
    );
  }
}

/// The always-visible second row under the title: who made the activity and
/// its at-a-glance facts (L2, level, participant count, rating). It sits above
/// the scrollable body so a map explorer sees the essentials without expanding
/// the sheet. Creator is fixed to PangeaChat until learners can author their
/// own activities. See activity-start-page.instructions.md.
class _ActivityStartInfoRow extends StatelessWidget {
  final ActivityPlanModel activity;

  const _ActivityStartInfoRow({required this.activity});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final language = PLanguageStore.byLangCode(activity.req.targetLanguage);
    final onVariant = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12.0, 0.0, 8.0, 8.0),
      child: Row(
        children: [
          Container(
            width: 28.0,
            height: 28.0,
            padding: const EdgeInsets.all(5.0),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: const PangeaLogoSvg(width: 18.0),
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: Text(
              'PangeaChat',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8.0),
          // Never empty: the flag when the language resolves to one, else a
          // langcode chip (shared with the analytics cluster's flag).
          LanguageFlagChip(
            language: language,
            langCode: activity.req.targetLanguage,
            width: 24.0,
            height: 18.0,
            fontSize: 12.0,
            radius: 3.0,
            borderWidth: 1.0,
            alwaysShowCode: false,
          ),
          const SizedBox(width: 12.0),
          _IconLabel(
            icon: Icons.school_outlined,
            label: activity.req.cefrLevel.string,
            color: onVariant,
          ),
          const SizedBox(width: 12.0),
          _IconLabel(
            icon: Icons.group_outlined,
            label: '${activity.req.numberOfParticipants}',
            color: onVariant,
          ),
          const SizedBox(width: 8.0),
          ActivityRatingMeter(
            average: activity.ratingAverage,
            count: activity.ratingCount,
          ),
        ],
      ),
    );
  }
}

/// A compact icon + text pair for the info row's level and participant facts.
class _IconLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _IconLabel({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18.0, color: color),
        const SizedBox(width: 4.0),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// Web's share and flag actions, sitting under the info row as two
/// de-emphasized bare-outline buttons (mobile puts them in the bottom CTA row
/// instead). See activity-start-page.instructions.md.
class _ActivityStartShareFlagRow extends StatelessWidget {
  final ActivitySessionStartState controller;

  const _ActivityStartShareFlagRow(this.controller);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20.0),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 8.0),
      child: Row(
        spacing: 8.0,
        children: [
          Expanded(
            child: Tooltip(
              message: l10n.share,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(shape: shape),
                onPressed: controller.copyActivityLink,
                child: const Icon(Icons.share_outlined),
              ),
            ),
          ),
          Expanded(
            child: Tooltip(
              message: l10n.feedbackButton,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(shape: shape),
                onPressed: controller.submitActivityFeedback,
                child: const Icon(Icons.flag_outlined),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Archived body for a removed activity with no plan recoverable from room
/// state (the last rung of the fallback ladder in activities.instructions.md):
/// the "no longer supported" notice, plus whatever the room itself holds —
/// each recorded role's occupant, role name, earned star count, and finished
/// status — so past progress stays reviewable.
class _ArchivedSessionFallbackBody extends StatelessWidget {
  final ActivitySessionStartState controller;

  const _ArchivedSessionFallbackBody(this.controller);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = controller.activityRoom;
    // All recorded roles — not just currently-joined members — so a learner
    // who left the room still shows in the review.
    final roles = room?.activityRoles?.roles.values.toList() ?? [];
    final awards = room?.orchestratorAwardedGoals;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600.0),
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          shrinkWrap: true,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 48.0,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(height: 16.0),
            Text(
              L10n.of(context).activityNoLongerSupported,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16.0),
            // This rung has no CTA footer to hang the leave action off, so the
            // way out sits with the notice that explains why there is no way
            // forward (#8064).
            if (controller.canLeaveArchivedSession) ...[
              ActivitySessionCTAButton(
                L10n.of(context).leave,
                controller.leaveArchivedSession,
              ),
              const SizedBox(height: 16.0),
            ],
            ...roles.map((role) {
              final user = room!.unsafeGetUserFromMemoryOrFallback(role.userId);
              final stars = awards?.awards[role.id]?.length ?? 0;
              return ListTile(
                leading: Avatar(
                  mxContent: user.avatarUrl,
                  name: user.localizedDisplayname(L10n.of(context)),
                  userId: role.userId,
                ),
                title: Text(user.localizedDisplayname(L10n.of(context))),
                subtitle: role.role == null ? null : Text(role.role!),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4.0,
                  children: [
                    if (stars > 0) ...[
                      const Icon(
                        Icons.star,
                        size: 18.0,
                        color: AppConfig.goldLight,
                      ),
                      Text('$stars'),
                    ],
                    if (role.isFinished)
                      const Padding(
                        padding: EdgeInsets.only(left: 8.0),
                        child: Icon(Icons.check_circle_outline, size: 18.0),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
