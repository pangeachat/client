import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/saved_analytics_extension.dart';
import 'package:fluffychat/features/analytics_data/analytics_init_error_indicator.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/features/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/roving_focus_group.dart';
import 'package:fluffychat/routes/analytics/analytics_navigation_util.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/start_practice.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/activity_star_row.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../../config/themes.dart';
import '../../../widgets/avatar.dart';

/// One joined course's plan, for the Learning Objectives page: its room and
/// its Missions in quest order, each with the activities that satisfy it in
/// this course (pins applied, activity-less Missions dropped — the same view
/// the course page shows).
class CourseMissions {
  final Room room;
  final List<QuestObjectiveGroup> groups;

  const CourseMissions({required this.room, required this.groups});

  /// Every joined course whose outline resolves, in the client's order.
  static Future<List<CourseMissions>> load(Client client) async {
    final courses = <CourseMissions>[];
    for (final room in client.joinedCourseRooms) {
      final questId = room.coursePlan?.uuid;
      if (questId == null) continue;
      final outline = (await QuestRepo.outline(
        questId,
        courseRoomId: room.id,
      )).result;
      // silent-ok: a course whose outline fails is reported where it loads
      // (reportCourseOutlineFailure, once per room per session); this page
      // lists what resolved and leaves that course's sessions to the tail.
      if (outline == null) continue;
      courses.add(
        CourseMissions(
          room: room,
          groups: objectiveGroupsWithActivities(
            outline
                .restrictedTo(room.teacherMode.pinnedActivitiesByObjective)
                .groups,
          ),
        ),
      );
    }
    return courses;
  }
}

/// The Learning Objectives page (#9436, formerly Stars): the learner's
/// Missions across their joined courses, each with its XP meter and a Practice
/// button, and under each the saved sessions that fed it. Sessions outside
/// every joined course's plan close the list under "Other activities", so a
/// learner in no course still sees their record. Design:
/// activities.instructions.md, "The Learning Objectives list".
class ActivityArchive extends StatefulWidget {
  final Widget closeButton;
  const ActivityArchive({super.key, required this.closeButton});

  @override
  State<ActivityArchive> createState() => _ActivityArchiveState();
}

class _ActivityArchiveState extends State<ActivityArchive> {
  /// Loaded once per page: the outline reads are cached, and a new future per
  /// build would flicker the list on every analytics update.
  late final Future<List<CourseMissions>> _courses = CourseMissions.load(
    Matrix.of(context).client,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return StreamBuilder(
      stream: Matrix.of(
        context,
      ).analyticsDataService.updateDispatcher.activityAnalyticsStream.stream,
      builder: (context, _) {
        final analyticsService = Matrix.of(context).analyticsDataService;
        final client = Matrix.of(context).client;
        final Room? analyticsRoom = client.ownAnalyticsRoomLocalByL2;
        final archive = analyticsRoom?.archivedActivities ?? [];
        final selectedRoomId = GoRouterState.of(
          context,
        ).pathParameters['roomid'];
        final hasCourses = client.joinedCourseRooms.isNotEmpty;
        return Scaffold(
          appBar: AppBar(
            leading: Center(child: widget.closeButton),
            title: Text(
              l10n.learningObjectives,
              style: FluffyThemes.isColumnMode(context)
                  ? Theme.of(context).textTheme.titleLarge
                  : Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
            ),
            centerTitle: false,
            titleSpacing: 0,
          ),
          body: Padding(
            padding: const EdgeInsetsGeometry.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!analyticsService.hasInitError)
                  MaxWidthBody(
                    showBorder: false,
                    withScrolling: false,
                    padding: .only(top: 48),
                    addVerticalPadding: false,
                    child: InstructionsInlineTooltip(
                      instructionsEnum: archive.isEmpty && !hasCourses
                          ? InstructionsEnum.noSavedActivitiesYet
                          : InstructionsEnum.activityAnalyticsList,
                      padding: const EdgeInsets.all(8.0),
                    ),
                  ),
                Expanded(
                  child: analyticsService.hasInitError
                      ? AnalyticsInitErrorIndicator(
                          reinitialize: analyticsService.reinitialize,
                        )
                      : MaxWidthBody(
                          showBorder: false,
                          withScrolling: false,
                          padding: .fromLTRB(32, 0, 32, 48),
                          addVerticalPadding: false,
                          child: FutureBuilder(
                            future: _courses,
                            builder: (context, snapshot) =>
                                ValueListenableBuilder(
                                  valueListenable:
                                      QuestObjectivesLoader.sharedProgression,
                                  builder: (context, progression, _) =>
                                      _ObjectiveList(
                                        courses: snapshot.data ?? const [],
                                        progression: progression,
                                        archive: archive,
                                        selectedRoomId: selectedRoomId,
                                      ),
                                ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The page's list: per course, its Missions in order with their sessions
/// beneath, then the sessions no joined course's plan accounts for.
class _ObjectiveList extends StatelessWidget {
  final List<CourseMissions> courses;
  final ProgressionResolution progression;
  final List<Room> archive;
  final String? selectedRoomId;

  const _ObjectiveList({
    required this.courses,
    required this.progression,
    required this.archive,
    required this.selectedRoomId,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final placed = <String>{};
    final children = <Widget>[];
    for (final course in courses) {
      // One course is the common case and needs no heading over its
      // Missions; two or more are told apart by name.
      if (courses.length > 1) {
        children.add(
          _Heading(course.room.getLocalizedDisplayname(MatrixLocals(l10n))),
        );
      }
      final quest = progression.forCourse(course.room.id);
      for (final group in course.groups) {
        final ids = {for (final a in group.activities) a.activityId};
        // A session is listed once, under the first Mission its activity
        // serves — the add returns false for one already placed.
        final sessions = [
          for (final room in archive)
            if (ids.contains(room.activityId) && placed.add(room.id)) room,
        ];
        children.add(
          _MissionRow(
            group: group,
            progress: quest?.rollup[group.objective.id],
          ),
        );
        children.addAll(sessions.map(_row));
      }
    }
    final other = [
      for (final room in archive)
        if (!placed.contains(room.id)) room,
    ];
    if (other.isNotEmpty) {
      if (courses.isNotEmpty) children.add(_Heading(l10n.otherActivities));
      children.addAll(other.map(_row));
    }
    return Semantics(
      label: l10n.starListLabel,
      container: true,
      // One Tab stop for the session list, arrow keys inside; Tab lands on
      // the open session (#8935).
      child: RovingFocusGroup(
        ids: [for (final room in archive) room.id],
        selectedId: selectedRoomId,
        child: ListView(
          key: const PageStorageKey<String>('activity-archive'),
          physics: const ClampingScrollPhysics(),
          children: children,
        ),
      ),
    );
  }

  Widget _row(Room room) => AnalyticsActivityItem(
    room: room,
    rovingId: room.id,
    selected: room.id == selectedRoomId,
  );
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8.0, 16.0, 8.0, 4.0),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// A Mission's line: its star (a check once complete), its can-do statement,
/// its XP over the threshold when resolved, and Practice scoped to it
/// (#9438). The sessions that fed it follow as rows.
class _MissionRow extends StatelessWidget {
  final QuestObjectiveGroup group;
  final MissionProgress? progress;

  const _MissionRow({required this.group, required this.progress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final progress = this.progress;
    final satisfied = progress?.satisfied ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8.0, 12.0, 8.0, 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            spacing: 8.0,
            children: [
              // The star the Mission earned, once it has — nothing before,
              // so an XP count in progress is never read as a star count.
              // The slot stays so statements align down the list.
              SizedBox(
                width: 20.0,
                child: satisfied
                    ? Icon(
                        Icons.star,
                        size: 20.0,
                        color: theme.pangea.goldGraphic,
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  group.objective.objective,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: satisfied
                        ? theme.colorScheme.onSurfaceVariant
                        : null,
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              if (progress != null)
                Padding(
                  padding: const EdgeInsets.only(left: 28.0),
                  child: Semantics(
                    label: l10n.xpTowardObjective(
                      progress.xp,
                      progress.threshold,
                    ),
                    child: ExcludeSemantics(
                      child: Text(
                        l10n.xpOfThreshold(progress.xp, progress.threshold),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              // The full phrase is the button's accessible name; the visible
              // label stays short (the pattern of the analytics Practice
              // pill, #8726).
              Tooltip(
                message: l10n.practiceObjective,
                excludeFromSemantics: true,
                child: TextButton.icon(
                  onPressed: () => startPractice(
                    context,
                    ConstructTypeEnum.vocab,
                    missionId: group.objective.id,
                  ),
                  icon: const Icon(Symbols.fitness_center, size: 18.0),
                  label: Text(
                    l10n.practice,
                    semanticsLabel: l10n.practiceObjective,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AnalyticsActivityItem extends StatelessWidget {
  final Room room;
  final bool selected;

  /// This row's id in the enclosing [RovingFocusGroup]: the session list is
  /// one Tab stop, with the arrow keys moving between rows (#8935). Null for
  /// a row outside a group.
  final String? rovingId;

  const AnalyticsActivityItem({
    super.key,
    required this.room,
    this.selected = false,
    this.rovingId,
  });

  @override
  Widget build(BuildContext context) {
    final rovingId = this.rovingId;
    final focusNode = rovingId == null
        ? null
        : RovingFocusGroup.nodeOf(context, rovingId);

    final activity = room.activityPlan;
    // A v3 session's plan is hydrated from CMS, so it can be null (still
    // loading, or gone from the backend) and can land with an empty title. The
    // room was named after the activity at creation, so fall back to the room
    // name rather than a blank row (#9033) — the same rung the start page's
    // archived session lands on (activities.instructions.md).
    final planTitle = activity?.title ?? '';
    final title = planTitle.isNotEmpty
        ? planTitle
        : room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final goals = room.ownRole?.allGoals;

    final userId = room.client.userID;
    final summary = room.activitySummary?.summary;
    final cefrLevel = summary?.participants
        .firstWhereOrNull((p) => p.participantId == userId)
        ?.cefrLevel;

    // The level and the stats come and go together: a session with no
    // generated summary keeps its title and stars and shows neither, rather
    // than a half-filled row (activities.instructions.md, "The Stars list").
    final analytics = room.activitySummaryAnalytics;
    final stats = summary == null || analytics == null || userId == null
        ? null
        : _ActivitySessionStats(
            xp: analytics.xpForUser(userId),
            vocab: analytics.uniqueConstructCountForUser(
              userId,
              ConstructTypeEnum.vocab,
            ),
            grammar: analytics.uniqueConstructCountForUser(
              userId,
              ConstructTypeEnum.morph,
            ),
            onSelectedFill: selected,
          );

    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: selected ? theme.colorScheme.secondaryContainer : null,
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          clipBehavior: Clip.hardEdge,
          child: ListTile(
            focusNode: focusNode,
            visualDensity: const VisualDensity(vertical: -0.5),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: HoverBuilder(
              builder: (context, hovered) => AnimatedScale(
                duration: FluffyThemes.animationDuration,
                curve: FluffyThemes.animationCurve,
                scale: hovered ? 1.1 : 1.0,
                child: ExcludeSemantics(
                  child: Avatar(
                    borderRadius: BorderRadius.circular(4.0),
                    mxContent: room.avatar,
                    name: room.getLocalizedDisplayname(),
                  ),
                ),
              ),
            ),
            isThreeLine: stats != null,
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: goals == null && stats == null
                ? null
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2.0,
                    children: [
                      if (goals != null)
                        ActivityStarRow(
                          total: goals.length,
                          earned:
                              room
                                  .orchestratorAwardedGoals
                                  .awards[room.ownRoleState?.id]
                                  ?.length ??
                              0,
                          iconSize: 22.0,
                        ),
                      ?stats,
                    ],
                  ),
            trailing: cefrLevel != null
                ? Semantics(
                    label: L10n.of(context).difficultyLabel(cefrLevel),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: ExcludeSemantics(
                        child: Text(
                          cefrLevel.toUpperCase(),
                          style: const TextStyle(fontSize: 14.0),
                        ),
                      ),
                    ),
                  )
                : null,
            onTap: () {
              AnalyticsNavigationUtil.navigateToAnalytics(
                context: context,
                view: ProgressIndicatorEnum.activities,
                activityRoomId: room.id,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The learner's own numbers from a saved session: the XP they earned, and how
/// many distinct vocabulary and grammar items they used. All three come from
/// the summary saved with the session, so the row can never disagree with the
/// end-of-activity card (activities.instructions.md, "The Stars list").
class _ActivitySessionStats extends StatelessWidget {
  final int xp;
  final int vocab;
  final int grammar;

  /// Whether the row is drawn on the selected fill. The gold XP text falls
  /// below the 4.5:1 contrast floor there, so it takes the surface ink instead.
  final bool onSelectedFill;

  const _ActivitySessionStats({
    required this.xp,
    required this.vocab,
    required this.grammar,
    required this.onSelectedFill,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Wrap(
      spacing: 10.0,
      runSpacing: 2.0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.xpAmount(xp),
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: onSelectedFill
                ? theme.colorScheme.onSurface
                : theme.pangea.gold,
          ),
        ),
        _ActivitySessionStat(
          icon: ProgressIndicatorEnum.wordsUsed.icon,
          count: vocab,
          label: l10n.vocabItemsUsed(vocab),
        ),
        _ActivitySessionStat(
          icon: ProgressIndicatorEnum.morphsUsed.icon,
          count: grammar,
          label: l10n.grammarItemsUsed(grammar),
        ),
      ],
    );
  }
}

/// One count on the stats line: the analytics bar's icon for that kind of
/// item, the number, and the spoken [label] the number alone can't carry.
class _ActivitySessionStat extends StatelessWidget {
  final IconData icon;
  final int count;
  final String label;

  const _ActivitySessionStat({
    required this.icon,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 3.0,
          children: [
            Icon(icon, size: 15.0, color: theme.colorScheme.onSurfaceVariant),
            Text(
              "$count",
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
