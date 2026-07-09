import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_bottom_content.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_button_widget.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_start_hero.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_vocab_widget.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The location that closes a non-embedded activity plan opened as a room/
/// session token (the chat list / a left panel): it drops ONLY that token, so
/// the rest of the workspace — notably the chat list — survives. Closing an
/// activity (e.g. one stuck on an "activity not found" error) must not also
/// clear the chat list (#7156). Returns null when no such token is open — the
/// standalone `/<activityId>` route — so the caller pops or falls back to home.
@visibleForTesting
String? activityRoomCloseLocation(Uri uri, String? roomId) {
  if (roomId == null || roomId.isEmpty) return null;

  bool matches(PanelToken t) {
    if (t.type != PanelTypesEnum.room && t.type != PanelTypesEnum.session) {
      return false;
    }

    final param = t.param;
    if (param == null || param is! RoomTokenParam) return false;
    return shortRoomId(param.id) == shortRoomId(roomId);
  }

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

  String? _archivedRoomName(BuildContext context) {
    if (!controller.activityRemoved) return null;
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
                // Transient fetch failure — retryable, never the archived view
                // or the "no longer supported" notice (the fallback ladder in
                // activities.instructions.md engages only on a confirmed 404).
                : controller.error != null
                ? Center(
                    child: ErrorIndicator(
                      message: L10n.of(context).activityLoadFailed,
                    ),
                  )
                // Confirmed removed with no plan recoverable from room state:
                // archived body from role/goal state alone.
                : activity == null && controller.activityRemoved
                ? _ArchivedSessionFallbackBody(controller)
                : activity == null
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
            ...roles.map((role) {
              final user = room!.unsafeGetUserFromMemoryOrFallback(role.userId);
              final stars = awards?.awards[role.id]?.length ?? 0;
              return ListTile(
                leading: Avatar(
                  mxContent: user.avatarUrl,
                  name: user.calcDisplayname(),
                  userId: role.userId,
                ),
                title: Text(user.calcDisplayname()),
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
