import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/repo/quest_plans_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/spaces/public_course_extension.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/url_image_widget.dart';

class FindCoursePage extends StatefulWidget {
  const FindCoursePage({super.key});

  @override
  State<FindCoursePage> createState() => FindCoursePageState();
}

class FindCoursePageState extends State<FindCoursePage> {
  /// Session-scoped memory of the last language filter the learner picked while
  /// browsing public courses. Tapping a course opens the route-driven preview
  /// (`/courses/preview/:courseroomid`); backing out of it **remounts** this
  /// page, so without this the filter reset to the L2 default and lost the
  /// choice (#7230). Mirrors `NewCoursePageState._lastChosenLanguage` (#7269) —
  /// it survives the remount with no URL churn.
  static LanguageModel? _lastChosenLanguage;

  /// The language filter the browse list opens on: this session's last pick
  /// ([lastChosen], so the preview round-trip keeps it), else the learner's L2
  /// default (#7230).
  @visibleForTesting
  static LanguageModel? seedLanguage({
    required LanguageModel? lastChosen,
    required LanguageModel? l2Default,
  }) => lastChosen ?? l2Default;

  final TextEditingController searchController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  Timer? _coolDown;

  final ValueNotifier<bool> loading = ValueNotifier(false);
  final ValueNotifier<List<PublicCoursesChunk>> visibleCourses = ValueNotifier(
    [],
  );

  final ValueNotifier<LanguageModel?> targetLanguageFilter = ValueNotifier(
    null,
  );

  final List<PublicCoursesChunk> _resultsCache = [];
  Map<String, CoursePlanModel> coursePlans = {};
  String? nextBatch;
  bool fullyLoaded = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    LanguageModel? l2Default;
    final l2 = MatrixState.pangeaController.userController.userL2;
    if (l2 != null) {
      final availableLanguages =
          MatrixState.pangeaController.pLanguageStore.unlocalizedTargetOptions;
      l2Default = availableLanguages.contains(l2) ? l2 : l2.unlocalized;
    }
    // Keep the language picked this session across the preview round-trip
    // (#7230); fall back to the learner's L2 default.
    targetLanguageFilter.value = seedLanguage(
      lastChosen: _lastChosenLanguage,
      l2Default: l2Default,
    );
    loadMore();
  }

  @override
  void dispose() {
    searchController.dispose();
    scrollController.dispose();
    _coolDown?.cancel();
    visibleCourses.dispose();
    loading.dispose();
    targetLanguageFilter.dispose();
    super.dispose();
  }

  void setTargetLanguageFilter(LanguageModel? language) {
    if (targetLanguageFilter.value == language) return;
    targetLanguageFilter.value = language;
    _lastChosenLanguage =
        language; // remember for the rest of this session (#7230)
    visibleCourses.value = [];
    loading.value = false;
    _loadGeneration++;
    if (scrollController.hasClients) {
      scrollController.jumpTo(0);
    }
    searchController.clear();
    loadMore();
  }

  void onSearchEnter(String text, {bool globalSearch = true}) {
    if (text.isEmpty) {
      visibleCourses.value = [];
      loading.value = false;
      _loadGeneration++;
      loadMore();
      return;
    }

    _coolDown?.cancel();
    _coolDown = Timer(const Duration(milliseconds: 500), () {
      visibleCourses.value = [];
      loading.value = false;
      _loadGeneration++;
      loadMore();
    });
  }

  /// Get a sorted list of cached courses that:
  /// 1) Are not already in the list of visible courses
  /// 2) Are not a course that the user is already in
  /// 2) Have a course plan that matches the language filter
  /// 3) Match the search term, if any exists
  List<PublicCoursesChunk> _filterCourses(String targetLanguage) {
    final courses = List<PublicCoursesChunk>.from(_resultsCache);

    // filter out already visible courses
    final invisibleCourses = courses.where(
      (c) => !visibleCourses.value.any((v) => v.room.roomId == c.room.roomId),
    );

    // filter out joined courses
    final unjoinedCourses = invisibleCourses.where(
      (c) => !Matrix.of(context).client.rooms.any(
        (r) => r.id == c.room.roomId && r.membership == Membership.join,
      ),
    );

    // filter out rooms with 0 members
    final nonEmptyCourses = unjoinedCourses.where(
      (c) => c.room.numJoinedMembers > 0,
    );

    // filter out courses without relevant plans
    final targetLanguageCourses = nonEmptyCourses.where((chunk) {
      final course = coursePlans[chunk.courseId];
      if (course == null) return false;
      if (targetLanguage == "") return true;
      return course.targetLanguage.split('-').first == targetLanguage;
    });

    // filter by search term
    List<PublicCoursesChunk> filtered = targetLanguageCourses.toList();
    final searchText = searchController.text.trim().toLowerCase();
    if (searchText.isNotEmpty) {
      filtered = filtered.where((chunk) {
        final course = coursePlans[chunk.courseId];
        if (course == null) return false;
        final name = chunk.room.name?.toLowerCase() ?? '';
        return name.contains(searchText);
      }).toList();
    }

    // sort by
    // 1) beginning matching search term
    // 2) number of participants
    // 3) join rule (public > knock)
    filtered.sort((a, b) {
      final searchText = searchController.text.trim().toLowerCase();

      if (searchText.isNotEmpty) {
        final aName = a.room.name?.toLowerCase() ?? '';
        final bName = b.room.name?.toLowerCase() ?? '';

        final aStartsWith = aName.startsWith(searchText);
        final bStartsWith = bName.startsWith(searchText);

        if (aStartsWith && !bStartsWith) return -1;
        if (!aStartsWith && bStartsWith) return 1;
      }

      final participantsDiff =
          b.room.numJoinedMembers - a.room.numJoinedMembers;
      if (participantsDiff != 0) return participantsDiff;

      if (a.room.joinRule == JoinRules.public.name &&
          b.room.joinRule == JoinRules.knock.name) {
        return -1;
      } else if (a.room.joinRule == JoinRules.knock.name &&
          b.room.joinRule == JoinRules.public.name) {
        return 1;
      }
      return 0;
    });

    return filtered;
  }

  Future<void> loadMore({bool loadMore = false}) async {
    if (loading.value) return;
    loading.value = true;

    final int generation = _loadGeneration;
    final targetLanguage = targetLanguageFilter.value?.langCodeShort ?? "";

    // First, get any courses from the cache that should be visible and show
    visibleCourses.value = [
      ...visibleCourses.value,
      ..._filterCourses(targetLanguage),
    ];

    // Then, load until at least 5 courses are visible, or all courses have been loaded
    int timesLoaded = 0;
    while (_loadGeneration == generation &&
        loading.value &&
        (visibleCourses.value.length < 5 || loadMore) &&
        timesLoaded < 4 &&
        !fullyLoaded) {
      await _loadNextBatch();
      if (!mounted || _loadGeneration != generation) return;
      visibleCourses.value = [
        ...visibleCourses.value,
        ..._filterCourses(targetLanguage),
      ];
      timesLoaded++;
    }

    // Only update loading state if this load is still the current one.
    if (mounted && _loadGeneration == generation) {
      loading.value = false;
    }
  }

  /// Load and cache the next 10 public courses and course plans if applicable
  Future<void> _loadNextBatch() async {
    if (fullyLoaded) return;
    final coursesResult = await _requestPublicCourses();
    if (coursesResult.isError) {
      loading.value = false;
      return;
    }

    final coursesResp = coursesResult.result!;
    nextBatch = coursesResp.nextBatch;
    if (nextBatch == null) {
      fullyLoaded = true;
    }

    for (final course in coursesResp.courses) {
      if (!_resultsCache.any((c) => c.room.roomId == course.room.roomId)) {
        _resultsCache.add(course);
      }
    }

    final undiscoveredCourseIds = coursesResp.courses
        .where((c) => !coursePlans.containsKey(c.courseId))
        .map((c) => c.courseId)
        .toSet()
        .toList();

    final coursePlansResult = await _requestCoursePlans(undiscoveredCourseIds);
    if (coursePlansResult.isError) {
      loading.value = false;
      return;
    }

    final searchResult = coursePlansResult.result!;
    for (final entry in searchResult.entries) {
      coursePlans[entry.key] = entry.value;
    }
  }

  Future<Result<PublicCoursesResponse>> _requestPublicCourses() async {
    try {
      final resp = await Matrix.of(
        context,
      ).client.requestPublicCourses(since: nextBatch);
      return Result.value(resp);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'nextBatch': nextBatch});
      return Result.error(e);
    }
  }

  Future<Result<Map<String, CoursePlanModel>>> _requestCoursePlans(
    List<String> courseIds,
  ) async {
    try {
      // world_v2: resolve each public-course id from the v3 quest-plans layer.
      final plans = <String, CoursePlanModel>{};
      for (final id in courseIds) {
        final quest = await QuestPlansRepo.get(id);
        if (quest != null) plans[id] = quest;
      }
      return Result.value(plans);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'courseIds': courseIds});
      return Result.error(e);
    }
  }

  void startNewCourse() {
    // world_v2: open the start-my-own list as an `addcourse:own/<lang>` (or
    // `addcourse:own/all` with no language filter) left panel over the map —
    // the language/showAll choice folded into the token param instead of a
    // loose `?lang=`/`?showAll=` query (routing.instructions.md).
    final targetLanguage = targetLanguageFilter.value?.langCode;
    context.go(
      WorkspaceNav.openAddCourse(
        GoRouterState.of(context).uri,
        subpage: 'own',
        targetLanguage: targetLanguage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FindCoursePageView(controller: this);
  }
}

class FindCoursePageView extends StatelessWidget {
  final FindCoursePageState controller;

  const FindCoursePageView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => context.go(
            WorkspaceNav.openAddCourse(GoRouterState.of(context).uri),
          ),
        ),
        title: Text(
          L10n.of(context).browsePublicCourses,
          style: FluffyThemes.isColumnMode(context)
              ? theme.textTheme.titleLarge
              : theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
        ),
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: L10n.of(context).close,
            onPressed: () => context.go('/'),
          ),
        ],
      ),
      body: MaxWidthBody(
        showBorder: false,
        withScrolling: false,
        maxWidth: 600.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            spacing: 16.0,
            children: [
              ListenableBuilder(
                listenable: Listenable.merge([
                  controller.visibleCourses,
                  controller.loading,
                  controller.searchController,
                ]),
                builder: (context, _) {
                  final courses = controller.visibleCourses.value;
                  final loading = controller.loading.value;
                  if (courses.isEmpty &&
                      !loading &&
                      controller.nextBatch == null) {
                    return Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        spacing: 12.0,
                        children: [
                          const BotFace(
                            expression: BotExpression.addled,
                            width: Avatar.defaultSize * 1.5,
                          ),
                          Text(
                            L10n.of(context).noPublicCoursesFound,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge,
                          ),
                          ElevatedButton(
                            onPressed: controller.startNewCourse,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onPrimaryContainer,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [Text(L10n.of(context).startOwn)],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Expanded(
                    child: ListView.builder(
                      controller: controller.scrollController,
                      itemCount: courses.length + 1,
                      itemBuilder: (context, index) {
                        if (index == courses.length) {
                          return Center(
                            child: loading
                                ? CircularProgressIndicator.adaptive()
                                : !controller.fullyLoaded
                                ? TextButton(
                                    onPressed: () =>
                                        controller.loadMore(loadMore: true),
                                    child: Text(L10n.of(context).loadMore),
                                  )
                                : SizedBox(),
                          );
                        }
                        final space = courses[index];
                        return _PublicCourseTile(
                          chunk: space,
                          course: controller.coursePlans[space.courseId],
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicCourseTile extends StatelessWidget {
  final PublicCoursesChunk chunk;
  final CoursePlanModel? course;

  const _PublicCourseTile({required this.chunk, this.course});

  void _navigateToCoursePage(BuildContext context) {
    // The live public-preview route (route-driven; the Completer/preview flow
    // isn't token-native yet). See routing.instructions.md.
    context.go(
      '${PRoutes.courses}/preview/${Uri.encodeComponent(chunk.room.roomId)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final space = chunk.room;
    final courseId = chunk.courseId;
    final course = this.course;
    final displayname =
        space.name ?? space.canonicalAlias ?? L10n.of(context).emptyChat;
    final isKnock = space.joinRule == JoinRules.knock.name;

    return FocusTraversalGroup(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10.0),
        child: Material(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12.0),
          child: InkWell(
            // Tapping the card scopes the map to this course's activities
            // (world_v2); the Knock/Join pill opens the join flow.
            onTap: () => MapContextController.set(CourseMapContext(courseId)),
            borderRadius: BorderRadius.circular(12.0),
            child: Container(
              padding: const EdgeInsets.all(10.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ImageByUrl(
                    imageUrl: space.avatarUrl,
                    width: 44.0,
                    borderRadius: BorderRadius.circular(10.0),
                    replacement: Avatar(
                      name: displayname,
                      borderRadius: BorderRadius.circular(10.0),
                      size: 44.0,
                    ),
                  ),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text(
                                  displayname,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8.0),
                            FilledButton.tonal(
                              onPressed: () => _navigateToCoursePage(context),
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                foregroundColor:
                                    theme.colorScheme.onPrimaryContainer,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                ),
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20.0),
                                ),
                              ),
                              child: Text(
                                isKnock
                                    ? L10n.of(context).knock
                                    : L10n.of(context).join,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8.0),
                        if (course != null)
                          Wrap(
                            spacing: 6.0,
                            runSpacing: 6.0,
                            children: [
                              _chip(
                                context,
                                Icons.language,
                                course.targetLanguage
                                    .split('-')
                                    .first
                                    .toUpperCase(),
                              ),
                              _chip(
                                context,
                                Icons.group,
                                '${space.numJoinedMembers}',
                              ),
                              _chip(
                                context,
                                Icons.location_on,
                                '${course.topicIds.length}',
                              ),
                              _chip(
                                context,
                                Icons.school,
                                course.cefrLevel.string.replaceFirst(
                                  'PREA1',
                                  'PRE-A1',
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13.0, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4.0),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
