import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' as sdk;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/analytics_access/join_room_analytics_consent_handler.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_builder.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/features/join_codes/knocked_rooms_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/chat_list/chat_list.dart';
import 'package:fluffychat/routes/chat_list/course_chats_view.dart';
import 'package:fluffychat/routes/chat_list/course_default_chats_enum.dart';
import 'package:fluffychat/routes/chat_list/default_chats_room_extension.dart';
import 'package:fluffychat/routes/chat_list/extended_space_rooms_chunk.dart';
import 'package:fluffychat/routes/chat_list/hierarchy_sync_update_extension.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/invite_dialog.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/public_room_bottom_sheet.dart';

class CourseChats extends StatefulWidget {
  final Client client;
  final String roomId;
  final String? activeChat;

  const CourseChats(
    this.roomId, {
    super.key,
    required this.activeChat,
    required this.client,
  });

  @override
  State<CourseChats> createState() => CourseChatsController();
}

class CourseChatsController extends State<CourseChats> with CoursePlanProvider {
  String get roomId => widget.roomId;
  Room? get space {
    final room = widget.client.getRoomById(widget.roomId);
    return room?.isSpace == true ? room : null;
  }

  List<SpaceRoomsChunk$2>? _discoveredChildren;
  StreamSubscription? _roomSubscription;
  String? _nextBatch;
  bool noMoreRooms = false;
  bool isLoading = false;

  Map<String, RoomSummaryResponse> _roomSummaries = {};

  @override
  void initState() {
    super.initState();

    final courseId = space?.coursePlan?.uuid;
    if (courseId != null) {
      loadCourse(courseId);
    }

    loadHierarchy(reload: true).then((_) => _joinDefaultChats());
    _setRoomSubscription();
  }

  @override
  void didUpdateWidget(covariant CourseChats oldWidget) {
    // initState doesn't re-run when navigating between spaces
    // via the navigation rail, so this accounts for that
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      final courseId = space?.coursePlan?.uuid;
      if (courseId != null) {
        loadCourse(courseId);
      }

      _setRoomSubscription();
      _discoveredChildren = null;
      _nextBatch = null;
      noMoreRooms = false;
      loadHierarchy(reload: true);
    }
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    super.dispose();
  }

  Set<String> get childrenIds =>
      space?.spaceChildren.map((c) => c.roomId).whereType<String>().toSet() ??
      {};

  List<Room> get joinedRooms => Matrix.of(context).client.rooms
      .where((room) => childrenIds.contains(room.id))
      .where((room) => !room.isHiddenRoom)
      .toList();

  List<Room> joinedActivities() =>
      joinedRooms.where((r) => r.isActivitySession).toList();

  List<SpaceRoomsChunk$2> get discoveredGroupChats =>
      (_discoveredChildren ?? [])
          .where(
            (chunk) =>
                chunk.roomType == null ||
                !chunk.roomType!.startsWith(PangeaRoomTypes.activitySession),
          )
          .toList();

  Map<String, List<ExtendedSpaceRoomsChunk>> get discoveredActivities {
    final discoveredChildren = _discoveredChildren;
    if (discoveredChildren == null) return {};

    final Map<String, List<ExtendedSpaceRoomsChunk>> sessionsMap = {};

    // world_v2: the discovered children are already scoped to this course
    // space, so any activity-session room here is a course activity — there is
    // no v1 course-plan activity-id set to filter against anymore.
    for (final chunk in discoveredChildren) {
      final summary = _roomSummaries[chunk.roomId];
      Logs().w("Summary: $summary");
      if (summary == null) {
        continue;
      }

      final activity = summary.resolvedActivityPlan;
      final roles = summary.activityRoles;
      final users = summary.joinedUsersWithRoles;

      if (activity == null || roles == null || users.isEmpty) {
        continue;
      }

      if (activity.req.numberOfParticipants <= users.length) {
        // Don't show full activities
        continue;
      }

      // If any user has archived the activity, don't show it.
      // It's possible for users to finish an activity and then for some of the
      // users to leave, but if the activity was archived by anyone, that means
      // it was full at some point.
      if (roles.roles.values.any((role) => role.isArchived)) {
        continue;
      }

      sessionsMap[activity.activityId] ??= [];
      sessionsMap[activity.activityId]!.add(
        ExtendedSpaceRoomsChunk(
          chunk: chunk,
          assignedRoles: users.values.toList(),
          activity: activity,
        ),
      );
    }

    return sessionsMap;
  }

  List<Room> get joinedChats =>
      joinedRooms.where((room) => !room.isActivitySession).toList();

  bool showDefaultChatCreation(CourseDefaultChatsEnum type) {
    if (space == null || !space!.isRoomAdmin) return false;
    return !space!.dismissedDefaultChat(type) && !space!.hasDefaultChat(type);
  }

  void _setRoomSubscription() {
    _roomSubscription?.cancel();
    _roomSubscription = widget.client.onSync.stream
        .where(
          (u) => u.hasHierarchyUpdate(
            roomId: widget.roomId,
            userID: widget.client.userID,
            childrenIds: childrenIds,
          ),
        )
        .listen((update) => loadHierarchy(reload: true, background: true));
  }

  Future<void> _joinDefaultChats() async {
    if (_discoveredChildren == null) return;
    final found = List<SpaceRoomsChunk$2>.from(_discoveredChildren!);

    final List<Future> joinFutures = [];
    for (final chunk in found) {
      if (chunk.canonicalAlias == null) continue;
      final alias = chunk.canonicalAlias!;

      final isDefaultChat =
          (alias.localpart ?? '').startsWith(
            SpaceConstants.announcementsChatAlias,
          ) ||
          (alias.localpart ?? '').startsWith(
            SpaceConstants.introductionChatAlias,
          );

      if (!isDefaultChat) continue;

      joinFutures.add(
        widget.client
            .joinRoom(alias)
            .then((_) {
              _discoveredChildren?.remove(chunk);
            })
            .catchError((e, s) {
              ErrorHandler.logError(
                e: e,
                s: s,
                data: {'alias': alias, 'spaceId': widget.roomId},
              );
              return null;
            }),
      );
    }

    if (joinFutures.isNotEmpty) {
      await Future.wait(joinFutures);
    }
  }

  Future<void> loadHierarchy({
    bool reload = false,
    bool background = false,
  }) async {
    final space = this.space;
    if (space == null) return;

    if (mounted) setState(() => isLoading = true);

    try {
      await _loadHierarchy(activeSpace: space, reload: reload);
      await _loadRoomSummaries();
    } catch (e, s) {
      Logs().w('Unable to load hierarchy', e, s);
      if (mounted) {
        final snackBar = SnackBar(
          content: Text(e.toLocalizedString(context)),
          showCloseIcon: true,
        );
        // Background sync reloads can fire repeatedly on a flaky request, so
        // only a foreground (user-opened/navigated) failure is announced to
        // screen readers; background failures still show the toast but stay
        // silent to avoid repeated announcements (#7203).
        if (background) {
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBarAnnounced(snackBar, assertive: true);
        }
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _loadRoomSummaries() async {
    final client = Matrix.of(context).client;
    final space = this.space;
    if (space == null) return;

    final roomSummariesResponse = await client.loadRoomSummaries(
      childrenIds.toList(),
      l1Code: MatrixState.pangeaController.userController.userL1Code,
    );
    _roomSummaries = roomSummariesResponse;
  }

  /// Internal logic of loadHierarchy. It will load the hierarchy of
  /// the active space id (or specified spaceId).
  /// If [reload] is true, it will reload the entire hierarchy (used when room
  /// is added/removed from the space)
  /// If [reload] is false, it will load the next set of rooms
  Future<void> _loadHierarchy({
    required Room activeSpace,
    bool reload = false,
  }) async {
    // Load all of the space's state events. Space Child events
    // are used to filtering out unsuggested, unjoined rooms.
    final requestSpaceId = widget.roomId;
    await activeSpace.postLoad();

    // The current number of rooms loaded for this space that are visible in the UI
    final int prevLength = !reload ? (_discoveredChildren?.length ?? 0) : 0;

    // Failsafe to prevent too many calls to the server in a row
    int callsToServer = 0;

    List<SpaceRoomsChunk$2>? currentHierarchy =
        _discoveredChildren == null || reload
        ? null
        : List.from(_discoveredChildren!);
    String? currentNextBatch = reload ? null : _nextBatch;

    // Makes repeated calls to the server until 10 new visible rooms have
    // been loaded, or there are no rooms left to load. Using a loop here,
    // rather than one single call to the endpoint, because some spaces have
    // so many invisible rooms (analytics rooms) that it might look like
    // pressing the 'load more' button does nothing (Because the only rooms
    // coming through from those calls are analytics rooms).
    while (callsToServer < 5) {
      // if this space has been loaded and there are no more rooms to load, break
      if (currentHierarchy != null && currentNextBatch == null) {
        break;
      }

      // if this space has been loaded and 10 new rooms have been loaded, break
      final int currentLength = currentHierarchy?.length ?? 0;
      if (currentLength - prevLength >= 10) {
        break;
      }

      // make the call to the server
      final response = await widget.client.getSpaceHierarchy(
        widget.roomId,
        maxDepth: 1,
        from: currentNextBatch,
        limit: 100,
      );

      if (widget.roomId != requestSpaceId) {
        // The user has navigated to a different space since this call was made, so we should discard the response and not update the state
        return;
      }

      callsToServer++;

      if (response.nextBatch == null) {
        noMoreRooms = true;
      }

      // if rooms have earlier been loaded for this space, add those
      // previously loaded rooms to the front of the response list
      response.rooms.insertAll(0, currentHierarchy ?? []);

      // finally, set the response to the last response for this space
      // and set the current next batch token
      currentHierarchy = _filterHierarchyResponse(activeSpace, response.rooms);
      currentNextBatch = response.nextBatch;
    }

    if (widget.roomId != requestSpaceId) {
      // The user has navigated to a different space since the first call was made, so we should discard the response and not update the state
      return;
    }

    _discoveredChildren = currentHierarchy;
    _discoveredChildren?.sort(_sortSpaceChildren);
    _nextBatch = currentNextBatch;
  }

  List<SpaceRoomsChunk$2> _filterHierarchyResponse(
    Room space,
    List<SpaceRoomsChunk$2> hierarchyResponse,
  ) {
    final List<SpaceRoomsChunk$2> filteredChildren = [];
    for (final child in hierarchyResponse) {
      if (child.roomId == widget.roomId) {
        continue;
      }

      final room = space.client.getRoomById(child.roomId);
      if (room != null && room.membership != Membership.leave) {
        // If the room is already joined or invited, skip it
        continue;
      }

      final isDuplicate = filteredChildren.any(
        (filtered) => filtered.roomId == child.roomId,
      );
      if (isDuplicate) continue;

      if (_includeSpaceChild(space, child)) {
        filteredChildren.add(child);
      }
    }
    return filteredChildren;
  }

  bool _includeSpaceChild(Room space, SpaceRoomsChunk$2 hierarchyMember) {
    if (!mounted) return false;
    final bool isAnalyticsRoom =
        hierarchyMember.roomType == PangeaRoomTypes.analytics;

    final bool isMember = [
      Membership.join,
      Membership.invite,
    ].contains(widget.client.getRoomById(hierarchyMember.roomId)?.membership);

    final bool isSuggested =
        space.spaceChildSuggestionStatus[hierarchyMember.roomId] ?? true;

    return !isAnalyticsRoom && (isMember || isSuggested);
  }

  int _sortSpaceChildren(SpaceRoomsChunk$2 a, SpaceRoomsChunk$2 b) {
    final bool aIsSpace = a.roomType == 'm.space';
    final bool bIsSpace = b.roomType == 'm.space';

    if (aIsSpace && !bIsSpace) {
      return -1;
    } else if (!aIsSpace && bIsSpace) {
      return 1;
    }
    return 0;
  }

  Future<void> onChatTap(Room room) async {
    if (room.membership == Membership.invite) {
      if (room.hasKnocked) {
        if (!mounted) return;
        await showFutureLoadingDialog(
          context: context,
          future: () async {
            final waitForRoom = room.client.waitForRoomInSync(
              room.id,
              join: true,
            );
            await room.joinKnockedRoom();
            await waitForRoom;
          },
          exceptionContext: ExceptionContext.joinRoom,
        );
      } else {
        final inviteEvent = room.getState(
          EventTypes.RoomMember,
          room.client.userID!,
        );
        final matrixLocals = MatrixLocals(L10n.of(context));
        final action = await showInviteDialog<InviteAction>(
          context,
          title: room.getLocalizedDisplayname(matrixLocals),
          message: inviteEvent == null
              ? L10n.of(context).inviteForMe
              : inviteEvent.content.tryGet<String>('reason') ??
                    L10n.of(context).youInvitedBy(
                      room
                          .unsafeGetUserFromMemoryOrFallback(
                            inviteEvent.senderId,
                          )
                          .calcDisplayname(i18n: matrixLocals),
                    ),
          actions: [
            InviteDialogAction(
              label: L10n.of(context).accept,
              value: InviteAction.accept,
            ),
            InviteDialogAction(
              label: L10n.of(context).decline,
              value: InviteAction.decline,
              destructive: true,
            ),
            InviteDialogAction(
              label: L10n.of(context).block,
              value: InviteAction.block,
              destructive: true,
            ),
          ],
        );
        switch (action) {
          case null:
            return;
          case InviteAction.accept:
            break;
          case InviteAction.decline:
            await showFutureLoadingDialog(
              context: context,
              future: () => room.leave(),
            );
            return;
          case InviteAction.block:
            final userId = inviteEvent?.senderId;
            context.go(
              WorkspaceNav.openSettings(
                GoRouterState.of(context).uri,
                page: userId == null
                    ? 'security/ignorelist'
                    : 'security/ignorelist/$userId',
              ),
            );
            return;
        }
        if (!mounted) return;
        final joinResult = await showFutureLoadingDialog(
          context: context,
          future: () async {
            final waitForRoom = room.client.waitForRoomInSync(
              room.id,
              join: true,
            );
            await room.join();
            await waitForRoom;
          },
          exceptionContext: ExceptionContext.joinRoom,
        );
        if (joinResult.error != null) return;
      }
    }

    if (room.membership == Membership.ban) {
      ScaffoldMessenger.of(context).showSnackBarAnnounced(
        SnackBar(content: Text(L10n.of(context).youHaveBeenBannedFromThisChat)),
        assertive: true,
      );
      return;
    }

    if (room.membership == Membership.leave) {
      context.go(
        WorkspaceNav.openArchivedRoom(GoRouterState.of(context).uri, room.id),
      );
      return;
    }

    if (room.isSpace) {
      context.go(
        WorkspaceNav.openCourse(GoRouterState.of(context).uri, room.id),
      );
      return;
    }

    NavigationUtil.goToSpaceRoute(room.id, [], context);
  }

  Future<void> joinChildRoom(SpaceRoomsChunk$2 item) async {
    final space = this.space;
    final joinResp = await PublicRoomBottomSheet.show(
      context: context,
      chunk: item,
      via: space?.spaceChildren
          .firstWhereOrNull((child) => child.roomId == item.roomId)
          ?.via,
    );
    if (joinResp == null) return;

    final room = widget.client.getRoomById(joinResp.roomId);
    if (room == null) return;

    final handler = JoinRoomAnalyticsConsentHandler(joinResp, room);
    final joinedRoomId = await handler.handle(context);
    if (mounted && joinedRoomId != null) {
      setState(() {
        _discoveredChildren?.remove(item);
      });
      NavigationUtil.goToSpaceRoute(joinedRoomId, [], context);
    }
  }

  Future<void> joinActivity(
    String activityId,
    ExtendedSpaceRoomsChunk chunk,
  ) async {
    final hasRole = chunk.assignedRoles.any(
      (role) => role.userId == widget.client.userID,
    );
    final roomId = chunk.chunk.roomId;
    if (!hasRole) {
      context.go(
        WorkspaceNav.openCourseActivity(
          widget.roomId,
          activityId,
          roomId: roomId,
        ),
      );
      return;
    }

    await widget.client.joinRoom(
      roomId,
      via: space?.spaceChildren
          .firstWhereOrNull((child) => child.roomId == roomId)
          ?.via,
    );

    final room = widget.client.getRoomById(roomId);
    if (room == null || room.membership != Membership.join) {
      await widget.client.waitForRoomInSync(roomId, join: true);
    }

    if (widget.client.getRoomById(roomId) == null) {
      throw Exception("Failed to join room");
    }

    NavigationUtil.goToSpaceRoute(roomId, const [], context);
  }

  Future<void> dismissDefaultChatCreation(CourseDefaultChatsEnum type) async {
    final space = this.space;
    if (space == null) throw Exception("Room is null");
    await space.dismissDefaultChatCreation(type);
  }

  Future<void> createDefaultChat(CourseDefaultChatsEnum type) async {
    final space = this.space;
    if (space == null) throw Exception("Room is null");
    final roomId = await space.addDefaultChat(
      type: type,
      name: type.title(L10n.of(context)),
    );

    GoogleAnalytics.createChat(roomId);
    final classCode = space.joinCode;
    if (classCode != null) {
      GoogleAnalytics.addParent(roomId, classCode);
    }

    NavigationUtil.goToSpaceRoute(roomId, const [], context);
  }

  @override
  Widget build(BuildContext context) => CourseChatsView(this);
}
