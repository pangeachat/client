import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart' hide Visibility;

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics_access/course_settings_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_builder.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_client_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details_content.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class CourseInvitePage extends StatefulWidget {
  final String courseId;
  final Completer<String>? courseCreationCompleter;

  const CourseInvitePage(
    this.courseId, {
    super.key,
    this.courseCreationCompleter,
  });

  @override
  CourseInvitePageController createState() => CourseInvitePageController();
}

class CourseInvitePageController extends State<CourseInvitePage>
    with CoursePlanProvider {
  @override
  void initState() {
    super.initState();
    loadCourse(widget.courseId);
  }

  @override
  void didUpdateWidget(CourseInvitePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.courseId != widget.courseId) {
      loadCourse(widget.courseId);
    }
  }

  Future<String> getSpaceId() async {
    final completer = widget.courseCreationCompleter;
    if (completer == null) {
      // No live creation completer (reload / back). The route param is the
      // course PLAN uuid; the created space carries it in its coursePlan state
      // event, so resolve the already-created space rather than throwing. A
      // room matched this way already has that state, so no sync wait is needed.
      // (initState redirects away when no such room exists; this throw is a
      // belt-and-suspenders for that race.)
      final room = Matrix.of(context).client.getRoomByCourseId(widget.courseId);
      if (room == null) {
        throw Exception("No course room for plan ${widget.courseId}");
      }
      return room.id;
    }
    final spaceId = await completer.future;
    final room = Matrix.of(context).client.getRoomById(spaceId);

    final roomStateStream = Matrix.of(context).client.onRoomState.stream;
    final futures = [
      if (room == null) roomStateStream.firstWhere((e) => e.roomId == spaceId),
      if (room?.coursePlan == null)
        roomStateStream.firstWhere(
          (e) =>
              e.roomId == spaceId &&
              e.state.type == PangeaEventTypes.coursePlan,
        ),
      if (room?.requireAnalyticsAccess != true)
        roomStateStream.firstWhere(
          (e) =>
              e.roomId == spaceId &&
              e.state.type == PangeaEventTypes.courseSettings,
        ),
    ];

    if (futures.isNotEmpty) {
      await Future.wait(futures).timeout(const Duration(seconds: 10));
    }

    return spaceId;
  }

  Future<bool> get _isPublic async {
    String spaceId;
    try {
      spaceId = await getSpaceId();
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"created_course_id": widget.courseId},
      );
      return true;
    }

    try {
      final visibility = await Matrix.of(
        context,
      ).client.getRoomVisibilityOnDirectory(spaceId);
      return visibility == Visibility.public;
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {"space_id": spaceId});
      return true;
    }
  }

  Future<bool> get _requireAnalyticsAccess async {
    String spaceId;
    try {
      spaceId = await getSpaceId();
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"created_course_id": widget.courseId},
      );
      return true;
    }

    final room = Matrix.of(context).client.getRoomById(spaceId);
    if (room == null) return true;
    return room.requireAnalyticsAccess;
  }

  Future<void> _setVisibility(bool value) async {
    try {
      final spaceId = await getSpaceId();
      await Matrix.of(context).client.setRoomVisibilityOnDirectory(
        spaceId,
        visibility: value ? Visibility.public : Visibility.private,
      );
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"created_course_id": widget.courseId, "visibility": value},
      );
      rethrow;
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _setRequireAnalyticsAccess(bool value) async {
    try {
      final spaceId = await getSpaceId();
      final room = Matrix.of(context).client.getRoomById(spaceId);
      if (room == null) {
        throw Exception('Room not found');
      }

      await room.setRequireAnalyticsAccess(value);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"created_course_id": widget.courseId, "visibility": value},
      );
      rethrow;
    } finally {
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    const avatarSize = 44.0;

    final theme = Theme.of(context);
    final client = Matrix.of(context).client;

    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(20.0),
            constraints: const BoxConstraints(maxWidth: 750),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                course != null
                    ? Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppConfig.gold),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          spacing: 16.0,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              spacing: 10.0,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.map_outlined, size: 40.0),
                                Flexible(
                                  child: Text(
                                    course!.title,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            CourseInfoChips(
                              widget.courseId,
                              fontSize: 12.0,
                              iconSize: 12.0,
                            ),
                          ],
                        ),
                      )
                    : loadingCourse
                    ? const CircularProgressIndicator.adaptive()
                    : const SizedBox(),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    spacing: 16.0,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          const avatarSpace = avatarSize + 8.0;
                          final availableSpace = constraints.maxWidth - 24.0;

                          final visibleAvatars = min(
                            3,
                            (availableSpace / avatarSpace).floor() - 2,
                          );

                          return Row(
                            spacing: 8.0,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FutureBuilder(
                                future: client.getProfileFromUserId(
                                  client.userID!,
                                ),
                                builder: (context, snapshot) {
                                  return Avatar(
                                    size: avatarSize,
                                    mxContent: snapshot.data?.avatarUrl,
                                    name:
                                        snapshot.data?.displayName ??
                                        client.userID!.localpart,
                                    userId: client.userID!,
                                  );
                                },
                              ),
                              Avatar(
                                userId: BotName.byEnvironment,
                                size: avatarSize,
                              ),
                              ...List.generate(visibleAvatars, (index) {
                                return CircleAvatar(
                                  radius: avatarSize / 2,
                                  backgroundColor: AppConfig.gold.withAlpha(80),
                                  child: const Icon(Icons.person, size: 20.0),
                                );
                              }),
                              const Icon(Icons.more_horiz, size: 24.0),
                            ],
                          );
                        },
                      ),
                      Text(
                        L10n.of(context).courseStartDesc,
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                Column(
                  spacing: 24.0,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      constraints: BoxConstraints(maxWidth: 400.0),
                      child: Column(
                        spacing: 8.0,
                        children: [
                          Row(
                            spacing: 8.0,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  L10n.of(context).visibilityToggleTitle,
                                  style: theme.textTheme.bodyMedium,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              FutureBuilder(
                                future: _isPublic,
                                builder: (context, snapshot) {
                                  final value = snapshot.data ?? true;
                                  return Switch(
                                    value: value,
                                    onChanged: (v) => showFutureLoadingDialog(
                                      context: context,
                                      future: () => _setVisibility(v),
                                    ),
                                    activeThumbColor: AppConfig.success,
                                  );
                                },
                              ),
                            ],
                          ),
                          Row(
                            spacing: 8.0,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  L10n.of(context).requireAnalyticsAccessTitle,
                                  style: theme.textTheme.bodyMedium,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              FutureBuilder(
                                future: _requireAnalyticsAccess,
                                builder: (context, snapshot) {
                                  final value = snapshot.data ?? true;
                                  return Switch(
                                    value: value,
                                    onChanged: (v) => showFutureLoadingDialog(
                                      context: context,
                                      future: () =>
                                          _setRequireAnalyticsAccess(v),
                                    ),
                                    activeThumbColor: AppConfig.success,
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final resp = await showFutureLoadingDialog(
                          context: context,
                          future: getSpaceId,
                        );
                        if (mounted && !resp.isError) {
                          // world_v2: token nav, not the legacy /rooms/spaces
                          // path. go_router runs the legacy redirect once, but
                          // that path needs two passes to reach its token form,
                          // so it stranded on a blank /courses/:id page (#7082).
                          context.go(
                            WorkspaceNav.openCoursePageFor(
                              GoRouterState.of(context).uri,
                              resp.result!,
                              RoomSubpageEnum.invite,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                      ),
                      child: Row(
                        spacing: 8.0,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.upload_file),
                          Text(L10n.of(context).inviteYourFriends),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final resp = await showFutureLoadingDialog(
                          context: context,
                          future: getSpaceId,
                        );
                        if (mounted && !resp.isError) {
                          // world_v2: token nav to the course card (see #7082).
                          context.go(
                            WorkspaceNav.openCourse(
                              GoRouterState.of(context).uri,
                              resp.result!,
                              tab: SpaceSettingsTabs.course,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                      ),
                      child: Row(
                        spacing: 8.0,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [Text(L10n.of(context).playWithAI)],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
