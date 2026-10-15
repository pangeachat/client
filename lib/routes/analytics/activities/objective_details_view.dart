import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/saved_analytics_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/activities/activity_archive.dart';
import 'package:fluffychat/routes/analytics/analytics_navigation_util.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/start_practice.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_vocab_widget.dart';
import 'package:fluffychat/routes/courses/course_objectives/activity_carousel.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_xp_ring.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Where a Mission's XP came from, summed over [group]'s activities from the
/// learner's saved sessions — the same activities the resolver's rollup
/// counts for that course — plus practice outside any session on its words.
MissionXpBreakdown missionBreakdownFor(
  Client client,
  QuestObjectiveGroup group,
) {
  final cache = MissionXpCache.instance;
  final byActivity = client.userXpBreakdownByActivity(
    chatXpByRoom: cache.chatXpByRoom,
    practiceXpByRoom: cache.practiceXpByRoom,
  );
  var sum = MissionXpBreakdown.zero;
  for (final activity in group.activities) {
    sum = sum + (byActivity[activity.activityId] ?? MissionXpBreakdown.zero);
  }
  return sum +
      MissionXpBreakdown(
        practice: practiceXpForLemmas(group.lemmas, cache.practiceXpByLemma),
      );
}

/// A Learning Objective's detail page (#9420 prototype), opened from the
/// Learning Objectives list the way a word's page opens from the vocab list:
/// the can-do with its star and XP ring, then the activities the learner has
/// finished toward it as a scrolling row of stamped cards, then the course's
/// words for it. Read from the first
/// joined course that carries the Mission, as the list does.
class ObjectiveDetailsView extends StatefulWidget {
  final String missionId;
  final Widget closeButton;

  const ObjectiveDetailsView({
    required this.missionId,
    required this.closeButton,
    super.key,
  });

  @override
  State<ObjectiveDetailsView> createState() => _ObjectiveDetailsViewState();
}

class _ObjectiveDetailsViewState extends State<ObjectiveDetailsView> {
  late final Future<List<CourseMissions>> _courses = CourseMissions.load(
    Matrix.of(context).client,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: Center(child: widget.closeButton),
        title: Text(
          l10n.learningObjective,
          style: FluffyThemes.isColumnMode(context)
              ? theme.textTheme.titleLarge
              : theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
        ),
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          // The vocab and grammar pages' Practice pill (primary, icon and
          // the short label), so practice looks the same wherever it starts.
          Tooltip(
            message: l10n.practiceObjective,
            excludeFromSemantics: true,
            child: FilledButton.icon(
              onPressed: () => startPractice(
                context,
                ConstructTypeEnum.vocab,
                missionId: widget.missionId,
              ),
              icon: const Icon(Symbols.fitness_center, size: 18),
              label: Text(
                l10n.practice,
                semanticsLabel: l10n.practiceObjective,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8.0),
        ],
      ),
      body: StreamBuilder(
        stream: Matrix.of(
          context,
        ).analyticsDataService.updateDispatcher.activityAnalyticsStream.stream,
        builder: (context, _) => FutureBuilder(
          future: _courses,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator.adaptive());
            }
            CourseMissions? course;
            QuestObjectiveGroup? group;
            for (final candidate in snapshot.data!) {
              for (final g in candidate.groups) {
                if (g.objective.id == widget.missionId) {
                  course = candidate;
                  group = g;
                  break;
                }
              }
              if (group != null) break;
            }
            if (course == null || group == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    l10n.objectiveNotInYourCourses,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListenableBuilder(
              listenable: Listenable.merge([
                QuestObjectivesLoader.sharedProgression,
                MissionXpCache.instance,
              ]),
              builder: (context, _) => _ObjectiveDetailsBody(
                course: course!,
                group: group!,
                progress: QuestObjectivesLoader.sharedProgression.value
                    .forCourse(course.room.id)
                    ?.rollup[widget.missionId],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ObjectiveDetailsBody extends StatelessWidget {
  final CourseMissions course;
  final QuestObjectiveGroup group;
  final MissionProgress? progress;

  const _ObjectiveDetailsBody({
    required this.course,
    required this.group,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;

    // The course's words for this objective: every suggested word across its
    // activities, once per lemma.
    final vocab = <String, Vocab>{};
    String? langCode;
    for (final activity in group.activities) {
      langCode ??= activity.plan.req.targetLanguage;
      for (final word in activity.plan.vocab) {
        vocab.putIfAbsent(word.lemma.toLowerCase(), () => word);
      }
    }

    // Only what the learner has finished and saved, in plan order — the
    // record of the objective, not what they could do next (#9420
    // prototype); each card wears its stamp and ×N, and opens the latest
    // saved session.
    final archive = client.ownAnalyticsRoomLocalByL2?.archivedActivities ?? [];
    final sessionsByActivity = <String, List<Room>>{};
    for (final session in archive) {
      final id = session.activityId;
      if (id != null) (sessionsByActivity[id] ??= []).add(session);
    }
    final activities = [
      for (final activity in group.activities)
        if (sessionsByActivity.containsKey(activity.activityId)) activity,
    ];

    return MaxWidthBody(
      maxWidth: 600.0,
      showBorder: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20.0, 8.0, 20.0, 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 24.0,
          children: [
            _CourseLink(room: course.room, missionId: group.objective.id),
            _ObjectiveHero(
              statement: group.objective.objective,
              progress: progress,
              breakdown: missionBreakdownFor(client, group),
            ),
            _Section(
              title: l10n.completedActivitiesTitle(activities.length),
              child: activities.isEmpty
                  ? Text(
                      l10n.noObjectiveActivitiesYet,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  : ActivityCarousel(
                      activities: activities,
                      onTap: (activity) =>
                          AnalyticsNavigationUtil.navigateToAnalytics(
                            context: context,
                            view: ProgressIndicatorEnum.activities,
                            activityRoomId:
                                sessionsByActivity[activity.activityId]!
                                    .last
                                    .id,
                          ),
                      userStarsByActivity: (id) =>
                          client.userStarsByActivity[id] ?? 0,
                      hasCompletedActivity: sessionsByActivity.containsKey,
                      timesCompletedByActivity: (id) =>
                          sessionsByActivity[id]?.length ?? 1,
                      liveStateByActivity: (_) => (
                        state: null,
                        openSessions: 0,
                        participants: const [],
                        openSlots: 0,
                      ),
                      availableParticipants: null,
                    ),
            ),
            // The activity page's own word chips: its "Suggested vocab"
            // heading, and a tap opens the word card in place.
            if (vocab.isNotEmpty && langCode != null)
              ActivityVocabWidget(
                vocab: vocab.values.toList(),
                langCode: langCode,
                activityLangCode: langCode,
                targetId: 'objective-vocab-${group.objective.id}',
                usedVocab: null,
                roomId: null,
              ),
          ],
        ),
      ),
    );
  }
}

/// The course this objective's page reads from, as a link back to it — on
/// the course page with this Mission picked.
class _CourseLink extends StatelessWidget {
  final Room room;
  final String missionId;

  const _CourseLink({required this.room, required this.missionId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Material(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(999.0),
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          onTap: () {
            final uri = GoRouterState.of(context).uri;
            context.go(
              WorkspaceNav.selectMission(
                Uri.parse(WorkspaceNav.openCourse(uri, room.id)),
                missionId,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4.0, 4.0, 10.0, 4.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8.0,
              children: [
                ExcludeSemantics(
                  child: Avatar(
                    mxContent: room.avatar,
                    name: name,
                    size: 24.0,
                    borderRadius: BorderRadius.circular(6.0),
                  ),
                ),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18.0,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 10.0,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      child,
    ],
  );
}

/// The top of the page: the star and statement, then the XP ring with what's
/// left to the star and where the XP came from.
class _ObjectiveHero extends StatelessWidget {
  final String statement;
  final MissionProgress? progress;
  final MissionXpBreakdown breakdown;

  const _ObjectiveHero({
    required this.statement,
    required this.progress,
    required this.breakdown,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context);
    final palette = MissionRingPalette.of(context);
    final numbers = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final progress = this.progress;
    final satisfied = progress?.satisfied ?? false;
    final threshold = progress?.threshold ?? 0;
    double share(int xp) => threshold <= 0 ? 0 : xp / threshold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 20.0,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10.0,
          children: [
            MissionStar(satisfied: satisfied, size: 44.0),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  statement,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Semantics(
              label: progress == null
                  ? null
                  : l10n.xpTowardObjective(progress.xp, progress.threshold),
              child: ExcludeSemantics(
                child: MissionXpRing(
                  size: 128.0,
                  strokeWidth: 14.0,
                  trackColor: palette.track,
                  gapColor: scheme.surface,
                  segments: [
                    MissionXpRingSegment(
                      fraction: share(breakdown.chat),
                      color: palette.chat,
                    ),
                    MissionXpRingSegment(
                      fraction: share(breakdown.goals),
                      color: palette.goals,
                    ),
                    MissionXpRingSegment(
                      fraction: share(breakdown.practice),
                      color: palette.practice,
                    ),
                  ],
                  child: progress == null
                      ? null
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              numbers.format(progress.xp),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.0,
                              ),
                            ),
                            Text(
                              '/ ${numbers.format(progress.threshold)} XP',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(width: 20.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10.0,
                children: [
                  if (progress != null)
                    Text(
                      satisfied
                          ? l10n.missionStarEarned
                          : l10n.xpToYourStar(
                              numbers.format(progress.threshold - progress.xp),
                            ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  for (final (color, label) in [
                    (
                      palette.chat,
                      l10n.xpFromChats(numbers.format(breakdown.chat)),
                    ),
                    (
                      palette.goals,
                      l10n.xpFromGoals(numbers.format(breakdown.goals)),
                    ),
                    (
                      palette.practice,
                      l10n.xpFromPractice(numbers.format(breakdown.practice)),
                    ),
                  ])
                    Row(
                      spacing: 8.0,
                      children: [
                        Container(
                          width: 12.0,
                          height: 12.0,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: scheme.outline),
                          ),
                        ),
                        Text(
                          label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A Mission's star: a dark outline while it's open, bright gold inside that
/// outline once earned — the outline carries the contrast on a light surface.
class MissionStar extends StatelessWidget {
  final bool satisfied;
  final double size;

  const MissionStar({required this.satisfied, required this.size, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: satisfied ? L10n.of(context).missionStarEarned : null,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (satisfied)
                Icon(
                  Icons.star_rounded,
                  size: size * 0.9,
                  color: theme.pangea.goldFixedDim,
                ),
              Icon(
                Icons.star_outline_rounded,
                size: size,
                color: theme.colorScheme.onSurface,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
