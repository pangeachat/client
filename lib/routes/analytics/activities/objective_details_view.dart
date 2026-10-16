import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
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
import 'package:fluffychat/routes/analytics/activities/objective_hero.dart';
import 'package:fluffychat/routes/analytics/analytics_navigation_util.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/start_practice.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_vocab_widget.dart';
import 'package:fluffychat/routes/courses/course_objectives/activity_carousel.dart';
import 'package:fluffychat/routes/courses/course_objectives/activity_live_state_room_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// A Learning Objective's detail page (#9420), opened from the
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
    final vocab = group.vocab;
    final langCode = group.activities.firstOrNull?.plan.req.targetLanguage;

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
            ObjectiveHero(
              statement: group.objective.objective,
              progress: progress,
              breakdown: client.missionXpBreakdown(group),
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
                      liveStateByActivity: (_) => noActivityLiveState,
                      availableParticipants: null,
                    ),
            ),
            // The activity page's own word chips: its "Suggested vocab"
            // heading, and a tap opens the word card in place.
            if (vocab.isNotEmpty && langCode != null)
              ActivityVocabWidget(
                vocab: vocab,
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
