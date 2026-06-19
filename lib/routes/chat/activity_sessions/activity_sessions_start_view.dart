import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_bottom_content.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_button_widget.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_summary_widget.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

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
    return StreamBuilder(
      stream: Matrix.of(context).client.onRoomState.stream
          .where((update) => update.roomId == controller.widget.roomId)
          .rateLimit(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final activity = controller.activity;
        // #Pangea
        // Opened in-place over a course via `?activity=<id>` (not the standalone
        // `/<activityId>` route): the AppBar IS the nav row — back returns to
        // the course, X closes, both just drop the param so the course stays.
        final uri = GoRouter.of(context).routeInformationProvider.value.uri;
        final embedded = uri.queryParameters['activity'] != null;
        // The activity plan is the course's CHILD (opened from its activity
        // list): its back-step reveals the parent — the course CARD. Drop the
        // activity overlay and, when a course is still scoped, reopen `left=course`
        // over the kept `?m=course:` filter (the parent is reconstructed from the
        // surviving scope, since the plan replaced the card to take the left
        // primary). When no course is scoped (opened from a world pin) the
        // back-step is just the map. Rebuild from the RAW query so the
        // `?m=course:` filter isn't re-encoded (`uri.replace(queryParameters:)`
        // turns `:`→`%3A`, which the raw-query parser can't read — the course
        // de-scopes and the reopened card, now an orphan, is dropped, landing on
        // the bare map). See `routing.instructions.md`.
        void returnToCourse() {
          final parts = uri.query.isEmpty ? <String>[] : uri.query.split('&');
          parts.removeWhere((p) =>
              p == 'activity' ||
              p.startsWith('activity=') ||
              p == 'roomid' ||
              p.startsWith('roomid=') ||
              p == 'launch' ||
              p.startsWith('launch=') ||
              p == 'autoplay' ||
              p.startsWith('autoplay='));
          final scoped = parts.any((p) => p.startsWith('m=course:'));
          final hasLeft =
              parts.any((p) => p == 'left' || p.startsWith('left='));
          if (scoped && !hasLeft) parts.add('left=course');
          GoRouter.of(context).go(parts.isEmpty ? '/' : '/?${parts.join('&')}');
        }

        // Pangea#
        return Scaffold(
          appBar: AppBar(
            leadingWidth: 52.0,
            title: activity == null
                ? null
                : Center(
                    child: Text(
                      activity.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: !FluffyThemes.isColumnMode(context)
                          ? const TextStyle(fontSize: 16)
                          : null,
                    ),
                  ),
            leading: Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Center(
                // #Pangea
                child: embedded
                    ? IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                        icon: const Icon(Icons.arrow_back),
                        onPressed: returnToCourse,
                      )
                    : IconButton(
                        tooltip: L10n.of(context).close,
                        icon: const Icon(Icons.close),
                        // On the first-class activity route this page is the
                        // bottom of the stack; popping would leave an empty
                        // navigator. Fall back to the home map.
                        onPressed: () => Navigator.of(context).canPop()
                            ? Navigator.of(context).pop()
                            : GoRouter.of(context).go(PRoutes.world),
                      ),
                // Pangea#
              ),
            ),
            actions: [
              IconButton(
                tooltip: L10n.of(context).feedbackButton,
                icon: const Icon(Icons.flag_outlined),
                onPressed: controller.submitActivityFeedback,
              ),
              // #Pangea
              // When embedded over a course (?activity=), the leading
              // back-arrow already closes the session toward the course — a
              // trailing X would be a redundant second control for the same
              // gesture (one close control per panel; see routing.instructions.md).
              // Pangea#
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
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 600.0),
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              children: [
                                ActivitySummary(
                                  activity: activity,
                                  room: controller.activityRoom,
                                  course: controller.courseParent,
                                  showInstructions: controller.showInstructions,
                                  toggleInstructions:
                                      controller.toggleInstructions,
                                  onTapParticipant:
                                      sessionController.selectRole,
                                  isParticipantSelected:
                                      sessionController.isRoleSelected,
                                  isParticipantShimmering:
                                      sessionController.isRoleShimmering,
                                  canSelectParticipant:
                                      sessionController.canSelectRole,
                                  assignedRoles: controller.assignedRoles,
                                ),
                                ActivitySessionBottomContent(sessionController),
                              ],
                            ),
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
