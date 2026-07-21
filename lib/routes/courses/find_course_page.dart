import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/repo/quest_plans_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/spaces/public_course_extension.dart';
import 'package:fluffychat/routes/courses/add_course_tile.dart';
import 'package:fluffychat/routes/courses/course_language_filter.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class FindCoursePage extends StatefulWidget {
  final Widget closeButton;
  final String? initialLanguageCode;
  final bool showAll;
  const FindCoursePage({
    super.key,
    required this.closeButton,
    this.initialLanguageCode,
    this.showAll = false,
  });

  @override
  State<FindCoursePage> createState() => FindCoursePageState();
}

class FindCoursePageState extends State<FindCoursePage> {
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
    final availableLanguages =
        MatrixState.pangeaController.pLanguageStore.unlocalizedTargetOptions;

    final l2 = MatrixState.pangeaController.userController.userL2;
    final initialLangCode = widget.initialLanguageCode;
    final initialLang = initialLangCode != null
        ? PLanguageStore.byLangCode(initialLangCode)
        : null;

    final targetLang = (initialLang == null && widget.showAll)
        ? null
        : availableLanguages.contains(initialLang)
        ? initialLang
        : availableLanguages.contains(initialLang?.unlocalized)
        ? initialLang?.unlocalized
        : availableLanguages.contains(l2)
        ? l2
        : availableLanguages.contains(l2?.unlocalized)
        ? l2?.unlocalized
        : null;

    targetLanguageFilter.value = targetLang;
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

  /// Clears the state that belongs to the previous catalog query.
  ///
  /// The language filter is a server-side query parameter, so cached results
  /// and the pagination cursor are scoped to the language they were fetched
  /// for. Carrying them across a filter change would re-show courses in the
  /// old language and resume paging with a cursor from a different query.
  void _resetQueryState() {
    _resultsCache.clear();
    coursePlans.clear();
    nextBatch = null;
    fullyLoaded = false;
  }

  void setTargetLanguageFilter(LanguageModel? language) {
    if (targetLanguageFilter.value == language) return;
    targetLanguageFilter.value = language;
    visibleCourses.value = [];
    _resetQueryState();
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
  /// 3) Have a resolved plan, so a card can be rendered for them
  /// 4) Match the search term, if any exists
  List<PublicCoursesChunk> _filterCourses() {
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

    // Eligibility — which rooms are courses, and which language they are in —
    // belongs to the catalog endpoint, which filters before it paginates. The
    // only reason a returned course is dropped here is that its plan did not
    // resolve, so there is no title to render a card with.
    // See public-courses.instructions.md in synapse-pangea-chat.
    final renderableCourses = unjoinedCourses.where(
      (c) => coursePlans[c.courseId] != null,
    );

    // filter by search term
    List<PublicCoursesChunk> filtered = renderableCourses.toList();
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

  /// How many courses one load should try to add before it stops.
  static const int _pageTarget = 5;

  /// Safety bound on network round trips per load. This is a guard against a
  /// pathological catalog, not the stopping condition — stopping on a batch
  /// count is what made "load more" give up while courses were still available
  /// (#7542).
  static const int _maxBatchesPerLoad = 10;

  Future<void> loadMore() async {
    if (loading.value) return;
    loading.value = true;

    final int generation = _loadGeneration;

    // Measured before anything is shown, so courses surfaced from the cache
    // count as progress for this load rather than triggering further round
    // trips for results the user can already see.
    final int startingCount = visibleCourses.value.length;

    // First, get any courses from the cache that should be visible and show
    visibleCourses.value = [...visibleCourses.value, ..._filterCourses()];

    int batches = 0;
    while (_loadGeneration == generation &&
        loading.value &&
        !fullyLoaded &&
        batches < _maxBatchesPerLoad &&
        visibleCourses.value.length - startingCount < _pageTarget) {
      await _loadNextBatch();
      if (!mounted || _loadGeneration != generation) return;
      visibleCourses.value = [...visibleCourses.value, ..._filterCourses()];
      batches++;
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
      final targetLanguage = targetLanguageFilter.value?.langCodeShort;
      final resp = await Matrix.of(context).client.requestPublicCourses(
        since: nextBatch,
        targetLanguage: targetLanguage?.isNotEmpty == true
            ? targetLanguage
            : null,
      );
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
      // world_v2: resolve the page's public-course ids from the v3 quest-plans
      // layer in one request. requireMissions is false because a course whose
      // quest has no missions is still a real course in the catalog — only the
      // creation picker refuses those (public-courses.instructions.md, #7700).
      final plans = await QuestPlansRepo.getMany(
        courseIds,
        requireMissions: false,
      );
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
      WorkspaceNav.openAddCoursePage(
        GoRouterState.of(context).uri,
        AddCourseSubpageEnum.own,
        initialLanguageFilter: targetLanguage,
        allLanguagesFilter: targetLanguage == null,
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
        leading: controller.widget.closeButton,
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
      body: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          constraints: const BoxConstraints(maxWidth: 450),
          child: Column(
            spacing: 20.0,
            children: [
              ValueListenableBuilder(
                valueListenable: controller.targetLanguageFilter,
                builder: (context, value, _) {
                  return CourseLanguageFilter(
                    value: controller.targetLanguageFilter.value,
                    onChanged: controller.setTargetLanguageFilter,
                  );
                },
              ),
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
                                    onPressed: () => controller.loadMore(),
                                    child: Text(L10n.of(context).loadMore),
                                  )
                                : SizedBox(),
                          );
                        }
                        final space = courses[index];
                        final coursePlan =
                            controller.coursePlans[space.courseId];
                        // Only courses with a resolved plan reach this list,
                        // so this is a defensive guard, not an expected
                        // branch — an unrenderable course must never occupy a
                        // row, or "load more" appears to do nothing.
                        if (coursePlan == null) {
                          return const SizedBox.shrink();
                        }

                        final lang =
                            controller.targetLanguageFilter.value?.langCode;
                        return AddCourseTile(
                          chunk: space,
                          coursePlan: coursePlan,
                          onTap: () => context.go(
                            WorkspaceNav.openAddCoursePage(
                              GoRouterState.of(context).uri,
                              AddCourseSubpageEnum.browse,
                              previewRoomId: space.room.roomId,
                              initialLanguageFilter: lang,
                              allLanguagesFilter: lang == null,
                            ),
                          ),
                          isKnock: space.room.joinRule == JoinRules.knock.name,
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
