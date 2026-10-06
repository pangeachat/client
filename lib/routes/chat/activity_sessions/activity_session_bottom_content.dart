import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/room_summaries/activity_summary_status_enum.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/features/tutorials/tutorial_target.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/user_profile_builder.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_badge.dart';
import 'package:fluffychat/routes/chat/activity_sessions/not_started_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/session_last_active_label.dart';
import 'package:fluffychat/routes/chat/activity_sessions/session_presence_tracker.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ActivitySessionBottomContent extends StatelessWidget {
  final ActivitySessionStateController controller;

  /// Tutorial target id for the open-sessions list, or null when this mount
  /// isn't the claimant ([TutorialTarget] — one claimant per id).
  final String? openSessionsTargetId;

  const ActivitySessionBottomContent(
    this.controller, {
    super.key,
    this.openSessionsTargetId,
  });

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;

    if (controller is NotStartedSessionController) {
      return _NotStartedSessionBottomContent(
        controller,
        openSessionsTargetId: openSessionsTargetId,
      );
    }

    return SizedBox();
  }
}

class _NotStartedSessionBottomContent extends StatelessWidget {
  final NotStartedSessionController controller;
  final String? openSessionsTargetId;

  const _NotStartedSessionBottomContent(
    this.controller, {
    required this.openSessionsTargetId,
  });

  @override
  Widget build(BuildContext context) {
    if (controller.subPage.visibleStatuses.isEmpty) {
      return const SizedBox.shrink();
    }

    // The session a course ping pointed at gets the bell badge, so a learner
    // choosing between several open sessions lands in the right one (#8319).
    final ping = CoursePingBadgeCache.instance.value;
    final pingedRoomId =
        ping != null &&
            ping.courseId == controller.widget.course?.id &&
            ping.activityId == controller.widget.activityId
        ? ping.sessionRoomId
        : null;

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: FluffyThemes.columnWidth * 1.5,
      ),
      child: Column(
        children: [
          ...controller.subPage.visibleStatuses.map((status) {
            // Completed is scoped per-viewer ([visibleCompletedSessions]); every
            // other status lists the whole course.
            final roomSummaries = status == ActivitySummaryStatus.completed
                ? controller.visibleCompletedSessions
                : controller.activityStatuses.getSessionsByStatus(status);

            if (roomSummaries.isEmpty) {
              if (status != ActivitySummaryStatus.notStarted) {
                return const SizedBox.shrink();
              }
              // The join list updates live, so its last session can fill
              // while it is open (#9134): say so instead of leaving the page
              // blank, and announce it to a screen reader watching the list.
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 36.0,
                  vertical: 32.0,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    L10n.of(context).noOpenSessions,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              );
            }

            final section = _ActivitySummaryStatusSection(
              status: status,
              roomSummaries: roomSummaries,
              pingedRoomId: pingedRoomId,
              onTap: controller.joinActivityByRoomId,
            );

            // Only the joinable (notStarted) section is a tutorial target, and
            // only when it has tiles — the target existing at all is what tells
            // the trigger the join list is showing with content. Its mount is
            // reported upward: on mobile it happens only after the sheet's
            // expand animation, past every other re-ask signal.
            if (status != ActivitySummaryStatus.notStarted) return section;
            return TutorialTarget(
              targetId: openSessionsTargetId,
              onMounted: controller.widget.controller.onTutorialSurfaceChanged,
              child: section,
            );
          }),
        ],
      ),
    );
  }
}

class _ActivitySummaryStatusSection extends StatefulWidget {
  final ActivitySummaryStatus status;
  final Map<String, RoomSummaryResponse> roomSummaries;

  /// The session room a course ping pointed at, or null — its tile gets the
  /// bell badge.
  final String? pingedRoomId;

  final Function(String) onTap;

  const _ActivitySummaryStatusSection({
    required this.status,
    required this.roomSummaries,
    required this.pingedRoomId,
    required this.onTap,
  });

  @override
  State<_ActivitySummaryStatusSection> createState() =>
      _ActivitySummaryStatusSectionState();
}

class _ActivitySummaryStatusSectionState
    extends State<_ActivitySummaryStatusSection> {
  /// Read by open sessions only: they sort and label by their members' last
  /// online time (#9333 prototype).
  late final SessionPresenceTracker _presence;

  bool get _isOpenList => widget.status == ActivitySummaryStatus.notStarted;

  @override
  void initState() {
    super.initState();
    _presence = SessionPresenceTracker(Matrix.of(context).client);
    _watchMembers();
  }

  @override
  void didUpdateWidget(_ActivitySummaryStatusSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _watchMembers();
  }

  @override
  void dispose() {
    _presence.dispose();
    super.dispose();
  }

  void _watchMembers() {
    if (!_isOpenList) return;
    _presence.watch([
      for (final summary in widget.roomSummaries.values)
        ..._joinedMembersOf(summary),
    ]);
  }

  /// Only members still in the session count toward its activity: someone
  /// who left or was only invited says nothing about who will answer.
  static Iterable<String> _joinedMembersOf(RoomSummaryResponse summary) =>
      summary.membershipSummary.entries
          .where((e) => e.value == Membership.join.name)
          .map((e) => e.key);

  /// The open roles of [summary], each flagged when the learner has already
  /// completed it in another session ([completedRoleIds]), so they can pick
  /// a session before joining (#9333 prototype).
  List<({String name, bool done})> _openRolesOf(
    RoomSummaryResponse summary,
    Set<String> completedRoleIds,
  ) {
    final plan = summary.resolvedActivityPlan;
    if (!_isOpenList || plan == null) return const [];
    return [
      for (final id in summary.openRoleIds)
        if (plan.roles[id] != null)
          (name: plan.roles[id]!.name, done: completedRoleIds.contains(id)),
    ];
  }

  DateTime? _lastActiveOf(RoomSummaryResponse summary) =>
      _isOpenList ? _presence.lastActiveOf(_joinedMembersOf(summary)) : null;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _presence,
      builder: (context, _) {
        final theme = Theme.of(context);
        final entries = widget.roomSummaries.entries.toList();
        final completedRoles = _isOpenList
            ? Matrix.of(context).client.completedRolesByActivity
            : const <String, Set<String>>{};
        if (_isOpenList) {
          // Most recently active first, so the sessions most likely to answer
          // are the easiest to join; room id breaks ties so the order holds
          // still between rebuilds.
          entries.sort((a, b) {
            final byRecent = SessionPresenceTracker.compareRecentFirst(
              _lastActiveOf(a.value),
              _lastActiveOf(b.value),
            );
            return byRecent != 0 ? byRecent : a.key.compareTo(b.key);
          });
        }
        return Padding(
          padding: const EdgeInsetsGeometry.symmetric(
            horizontal: 20.0,
            vertical: 16.0,
          ),
          child: Column(
            spacing: 12.0,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  widget.status.label(L10n.of(context), entries.length),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              for (final e in entries)
                _ActivitySessionDetailsTile(
                  roomSummary: e.value,
                  pinged: e.key == widget.pingedRoomId,
                  showLastActive: _isOpenList,
                  lastActive: _lastActiveOf(e.value),
                  openRoles: _openRolesOf(
                    e.value,
                    completedRoles[e.value.activityId] ?? const {},
                  ),
                  onTap: () => widget.onTap(e.key),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ActivitySessionDetailsTile extends StatelessWidget {
  final RoomSummaryResponse roomSummary;

  /// This session is the one a course ping pointed at: badge its corner.
  final bool pinged;

  /// An open session shows how recently its members were online.
  final bool showLastActive;
  final DateTime? lastActive;

  /// The seats a joiner can take, flagged when already completed.
  final List<({String name, bool done})> openRoles;

  final VoidCallback onTap;

  const _ActivitySessionDetailsTile({
    required this.roomSummary,
    required this.pinged,
    required this.showLastActive,
    required this.lastActive,
    this.openRoles = const [],
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activityRoles = roomSummary.activityRoles;
    final activitySummary = roomSummary.activitySummary;
    final textSummary = activitySummary?.summary?.summary;
    final analytics = roomSummary.activitySummaryAnalytics;
    final participants = roomSummary.membershipSummary.keys;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            borderRadius: BorderRadius.all(
              Radius.circular(AppConfig.borderRadius),
            ),
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.all(
                  Radius.circular(AppConfig.borderRadius),
                ),
              ),
              padding: EdgeInsets.all(12.0),
              child: Column(
                spacing: 24.0,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showLastActive || openRoles.isNotEmpty)
                    Wrap(
                      spacing: 12.0,
                      runSpacing: 6.0,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (showLastActive)
                          SessionLastActiveLabel(lastActive: lastActive),
                        for (final role in openRoles)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 4.0,
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 14.0,
                                color: theme.colorScheme.primary,
                              ),
                              Text(
                                L10n.of(context).openRole(role.name),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              if (role.done)
                                Tooltip(
                                  message: L10n.of(context).roleAlreadyDone,
                                  child: Icon(
                                    Icons.check_circle,
                                    size: 14.0,
                                    color: theme.pangea.success,
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  if (activitySummary != null)
                    Row(
                      spacing: 12.0,
                      children: [
                        Expanded(
                          child: Column(
                            spacing: 8.0,
                            children: [
                              if (textSummary != null) Text(textSummary),
                              if (analytics != null)
                                Row(
                                  spacing: 8.0,
                                  children: [
                                    Container(
                                      height: 20.0,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          AppConfig.borderRadius,
                                        ),
                                        color: theme
                                            .colorScheme
                                            .secondaryContainer,
                                      ),
                                      child: Row(
                                        spacing: 4.0,
                                        children: [
                                          Text(
                                            "XP",
                                            style: TextStyle(
                                              fontSize: 12.0,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            "${analytics.totalXP}",
                                            style: TextStyle(fontSize: 12.0),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      height: 20.0,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          AppConfig.borderRadius,
                                        ),
                                        color: theme
                                            .colorScheme
                                            .secondaryContainer,
                                      ),
                                      child: Row(
                                        spacing: 4.0,
                                        children: [
                                          Icon(
                                            ConstructTypeEnum
                                                .vocab
                                                .indicator
                                                .icon,
                                            size: 14.0,
                                          ),
                                          Text(
                                            "${analytics.totalUniqueConstructCount(ConstructTypeEnum.vocab)}",
                                            style: TextStyle(fontSize: 12.0),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      height: 20.0,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          AppConfig.borderRadius,
                                        ),
                                        color: theme
                                            .colorScheme
                                            .secondaryContainer,
                                      ),
                                      child: Row(
                                        spacing: 4.0,
                                        children: [
                                          Icon(
                                            ConstructTypeEnum
                                                .morph
                                                .indicator
                                                .icon,
                                            size: 14.0,
                                          ),
                                          Text(
                                            "${analytics.totalUniqueConstructCount(ConstructTypeEnum.morph)}",
                                            style: TextStyle(fontSize: 12.0),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.arrow_forward),
                          tooltip: L10n.of(context).details,
                          onPressed: onTap,
                        ),
                      ],
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          spacing: 16.0,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...participants.map((userId) {
                              final role = activityRoles?.role(userId);

                              final userSummary = activitySummary?.summary
                                  ?.userSummary(userId);

                              final superlative =
                                  userSummary?.superlatives.firstOrNull;

                              return ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: 90.0),
                                child: Opacity(
                                  opacity: role == null ? 0.5 : 1,
                                  child: Column(
                                    spacing: 6.0,
                                    children: [
                                      // Name and avatar both come from the user's
                                      // own profile: this tile lists sessions the
                                      // learner has NOT joined, so there is no
                                      // member state to resolve them from and the
                                      // course-member lookup this replaced left
                                      // everyone at their localpart with a default
                                      // avatar (#8192).
                                      UserProfileName(
                                        userId: userId,
                                        style: const TextStyle(fontSize: 12.0),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                      ),
                                      UserProfileAvatar(
                                        userId: userId,
                                        size: 60.0,
                                      ),
                                      if (userSummary != null)
                                        Text(
                                          userSummary.cefrLevel,
                                          style: const TextStyle(
                                            fontSize: 12.0,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      if (superlative != null)
                                        Text(
                                          superlative,
                                          style: const TextStyle(
                                            fontSize: 12.0,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      if (activitySummary == null) Icon(Icons.arrow_forward),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (pinged)
            const Positioned(top: -8.0, right: -8.0, child: CoursePingBadge()),
        ],
      ),
    );
  }
}
