import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/pangea/navigation/route_paths.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_chat/activity_summary_widget.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_bottom_content.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_button_widget.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_start_page.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_state_controller.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
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
                child: IconButton(
                  icon: const Icon(Icons.close),
                  // #Pangea
                  // On the first-class activity route this page is the
                  // bottom of the stack; popping would leave an empty
                  // navigator. Fall back to the home map.
                  onPressed: () => Navigator.of(context).canPop()
                      ? Navigator.of(context).pop()
                      : GoRouter.of(context).go(PRoutes.world),
                  // Pangea#
                ),
              ),
            ),
            actions: [
              IconButton(
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
