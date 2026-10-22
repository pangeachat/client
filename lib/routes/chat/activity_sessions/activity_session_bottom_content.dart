import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
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
import 'package:fluffychat/routes/chat/activity_sessions/sparkle_xp_text.dart';
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

            // The finished view also lists the learner's sessions from
            // other courses, so it has something to show even when this
            // course lists none.
            if (roomSummaries.isEmpty &&
                status != ActivitySummaryStatus.completed) {
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

            final section = status == ActivitySummaryStatus.completed
                ? ListenableBuilder(
                    // The XP figures follow the learner's XP as it is read.
                    listenable: MissionXpCache.instance,
                    builder: (context, _) => _completedSection(
                      context,
                      roomSummaries: roomSummaries,
                      pingedRoomId: pingedRoomId,
                    ),
                  )
                : _ActivitySummaryStatusSection(
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

  /// The learner's finished sessions of this activity (#9559): this course's
  /// first, then their saved sessions of it from other courses — or none —
  /// under "Other courses", so the list holds every session the total over
  /// the image counts. Each shows what it paid them; a listed session that
  /// paid them none (another learner's, for a course admin) shows no XP.
  Widget _completedSection(
    BuildContext context, {
    required Map<String, RoomSummaryResponse> roomSummaries,
    required String? pingedRoomId,
  }) {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final activityId = controller.widget.activityId;
    final credited = MissionXpCache.instance.creditedXpByRoom;
    final saved = {
      for (final room
          in client.savedSessionsByActivity[activityId] ?? const <Room>[])
        room.id: room,
    };
    final others = controller.otherCompletedSessions;
    final inCourse = controller.widget.course != null && others.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (roomSummaries.isNotEmpty)
          _ActivitySummaryStatusSection(
            status: ActivitySummaryStatus.completed,
            title: inCourse
                ? l10n.finishedInThisCourse(roomSummaries.length)
                : null,
            roomSummaries: roomSummaries,
            pingedRoomId: pingedRoomId,
            onTap: controller.joinActivityByRoomId,
            sessionXpOf: (roomId) =>
                _sessionXpOf(client, saved[roomId], credited),
          ),
        if (others.isNotEmpty)
          _ActivitySummaryStatusSection(
            status: ActivitySummaryStatus.completed,
            title: l10n.otherCoursesSessions(others.length),
            roomSummaries: others,
            pingedRoomId: null,
            onTap: controller.joinActivityByRoomId,
            sessionXpOf: (roomId) =>
                _sessionXpOf(client, saved[roomId], credited),
          ),
      ],
    );
  }

  /// What [session] paid the learner — its credited XP plus its goals — or
  /// null when it isn't one of their saved sessions.
  static int? _sessionXpOf(
    Client client,
    Room? session,
    Map<String, int> credited,
  ) => session == null ? null : client.sessionXp(session, credited);
}

class _ActivitySummaryStatusSection extends StatefulWidget {
  final ActivitySummaryStatus status;
  final Map<String, RoomSummaryResponse> roomSummaries;

  /// The section's title; null names it by [status] ("Finished (2)").
  final String? title;

  /// A finished session's XP for the learner, or null when it paid them
  /// none they can see.
  final int? Function(String roomId)? sessionXpOf;

  /// The session room a course ping pointed at, or null — its tile gets the
  /// bell badge.
  final String? pingedRoomId;

  final Function(String) onTap;

  const _ActivitySummaryStatusSection({
    required this.status,
    required this.roomSummaries,
    required this.pingedRoomId,
    required this.onTap,
    this.title,
    this.sessionXpOf,
  });

  @override
  State<_ActivitySummaryStatusSection> createState() =>
      _ActivitySummaryStatusSectionState();
}

class _ActivitySummaryStatusSectionState
    extends State<_ActivitySummaryStatusSection> {
  /// Read by open sessions only: they sort and label by their members' last
  /// online time.
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

  /// The names of [summary]'s open roles, so the learner can pick a session
  /// before joining.
  List<String> _openRolesOf(RoomSummaryResponse summary) {
    final plan = summary.resolvedActivityPlan;
    if (!_isOpenList || plan == null) return const [];
    return [
      for (final id in summary.openRoleIds)
        if (plan.roles[id] != null) plan.roles[id]!.name,
    ];
  }

  DateTime? _lastActiveOf(RoomSummaryResponse summary, DateTime now) =>
      _isOpenList
      ? _presence.lastActiveOf(_joinedMembersOf(summary), now: now)
      : null;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _presence,
      builder: (context, _) {
        final theme = Theme.of(context);
        final entries = widget.roomSummaries.entries.toList();
        final now = DateTime.now();
        if (_isOpenList) {
          // Most recently active first, so the sessions most likely to answer
          // are the easiest to join; room id breaks ties so the order holds
          // still between rebuilds.
          entries.sort((a, b) {
            final byRecent = SessionPresenceTracker.compareRecentFirst(
              _lastActiveOf(a.value, now),
              _lastActiveOf(b.value, now),
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
                child: Row(
                  spacing: 8.0,
                  children: [
                    Flexible(
                      child: Text(
                        widget.title ??
                            widget.status.label(
                              L10n.of(context),
                              entries.length,
                            ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (final e in entries)
                _ActivitySessionDetailsTile(
                  xp: widget.sessionXpOf?.call(e.key),
                  roomSummary: e.value,
                  pinged: e.key == widget.pingedRoomId,
                  showLastActive: _isOpenList,
                  lastActive: _lastActiveOf(e.value, now),
                  openRoles: _openRolesOf(e.value),
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

  /// The learner's XP from this session, or null to show none (#9559).
  final int? xp;

  /// This session is the one a course ping pointed at: badge its corner.
  final bool pinged;

  /// An open session shows how recently its members were online.
  final bool showLastActive;
  final DateTime? lastActive;

  /// The names of the seats a joiner can take.
  final List<String> openRoles;

  final VoidCallback onTap;

  const _ActivitySessionDetailsTile({
    required this.roomSummary,
    this.xp,
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
                              ExcludeSemantics(
                                child: Icon(
                                  Icons.person_outline,
                                  size: 14.0,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              Text(
                                L10n.of(context).openRole(role),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.primary,
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
                                    // The learner's own XP from the session
                                    // in the activity's XP look (#9559).
                                    if (xp case final xp? when xp > 0)
                                      SparkleXpText(
                                        text: L10n.of(context).xpAmount(xp),
                                        semanticsLabel: L10n.of(
                                          context,
                                        ).xpAmount(xp),
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
