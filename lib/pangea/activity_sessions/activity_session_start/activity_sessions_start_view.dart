import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_chat/activity_participant_list.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_bottom_content.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_button_widget.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_start_page.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_state_controller.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/common/widgets/url_image_widget.dart';
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
    final theme = Theme.of(context);
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
                  onPressed: () => Navigator.of(context).pop(),
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
                          child: Column(
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  SizedBox(
                                    height: 350.0,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) =>
                                          ImageByUrl(
                                            imageUrl: activity.imageURL,
                                            borderRadius: BorderRadius.zero,
                                            width: constraints.maxWidth,
                                          ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    top: 300.0,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.transparent,
                                            theme.colorScheme.surface.withAlpha(
                                              200,
                                            ),
                                            theme.colorScheme.surface,
                                          ],
                                          stops: [
                                            0.0,
                                            0.1,
                                            0.2,
                                          ], // fade completes very near the top
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Column(
                                      spacing: 12.0,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(12.0),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              AppConfig.borderRadius,
                                            ),
                                            color: theme.colorScheme.surface
                                                .withAlpha(180),
                                          ),
                                          child: Text(
                                            activity.description,
                                            style: theme.textTheme.bodyLarge
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurface,
                                                ),
                                          ),
                                        ),
                                        Row(
                                          spacing: 12.0,
                                          children: [
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 12.0,
                                                vertical: 6.0,
                                              ),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      AppConfig.borderRadius,
                                                    ),
                                                color: theme.colorScheme.surface
                                                    .withAlpha(180),
                                              ),
                                              child: Text(
                                                activity.req.cefrLevel.string,
                                              ),
                                            ),
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 12.0,
                                                vertical: 6.0,
                                              ),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      AppConfig.borderRadius,
                                                    ),
                                                color: theme.colorScheme.surface
                                                    .withAlpha(180),
                                              ),
                                              child: Text(
                                                L10n.of(
                                                  context,
                                                ).countParticipants(
                                                  activity.roles.length,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 12.0,
                                                vertical: 6.0,
                                              ),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      AppConfig.borderRadius,
                                                    ),
                                                color: theme.colorScheme.surface
                                                    .withAlpha(180),
                                              ),
                                              child: Text(activity.req.mode),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Positioned(
                                    top: 250.0,
                                    left: 16.0,
                                    right: 16.0,
                                    child: ActivityParticipantList(
                                      activity: activity,
                                      room: controller.activityRoom,
                                      assignedRoles: controller.assignedRoles,
                                      course: controller.courseParent,
                                      onTap: sessionController.selectRole,
                                      canSelect:
                                          sessionController.canSelectRole,
                                      isSelected:
                                          sessionController.isRoleSelected,
                                      isShimmering:
                                          sessionController.isRoleShimmering,
                                    ),
                                  ),
                                ],
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
