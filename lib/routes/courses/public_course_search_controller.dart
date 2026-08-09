import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/repo/quest_plans_repo.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/spaces/public_course_extension.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';
import 'package:fluffychat/routes/courses/course_search_controller.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class PublicCourseSearchController
    extends CourseSearchController<PublicCoursesChunk> {
  final Client client;
  PublicCourseSearchController({required this.client})
    : super(getCourseName: (p) => p.room.name ?? '');

  String? _nextBatch;
  final List<PublicCoursesChunk> _resultsCache = [];
  final Map<String, CoursePlanModel> _coursePlans = {};

  /// How many courses one load should try to add before it stops.
  static const int _pageTarget = 5;

  /// Safety bound on network round trips per load. This is a guard against a
  /// pathological catalog, not the stopping condition — stopping on a batch
  /// count is what made "load more" give up while courses were still available
  /// (#7542).
  static const int _maxBatchesPerLoad = 10;

  /// Get a sorted list of cached courses that:
  /// 1) Are not already in the list of visible courses
  /// 2) Are not a course that the user is already in
  /// 3) Have a resolved plan, so a card can be rendered for them
  /// 4) Match the search term, if any exists
  List<PublicCoursesChunk> get _coursesToAdd {
    final courses = List<PublicCoursesChunk>.from(_resultsCache);

    // filter out already visible courses
    final invisibleCourses = courses.where(
      (c) => !loadedCourses.any((v) => v.room.roomId == c.room.roomId),
    );

    // filter out joined courses
    final unjoinedCourses = invisibleCourses.where(
      (c) => !client.rooms.any(
        (r) => r.id == c.room.roomId && r.membership == Membership.join,
      ),
    );

    // Eligibility — which rooms are courses, and which language they are in —
    // belongs to the catalog endpoint, which filters before it paginates. The
    // only reason a returned course is dropped here is that its plan did not
    // resolve, so there is no title to render a card with.
    // See public-courses.instructions.md in synapse-pangea-chat.
    final renderableCourses = unjoinedCourses.where(
      (c) => _coursePlans[c.courseId] != null,
    );

    // filter by search term
    List<PublicCoursesChunk> filtered = renderableCourses.toList();
    final searchText = searchController.text.trim().toLowerCase();
    if (searchText.isNotEmpty) {
      filtered = filtered.where((chunk) {
        final course = _coursePlans[chunk.courseId];
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

  @override
  void reset() {
    _nextBatch = null;
    _coursePlans.clear();
    _resultsCache.clear();
  }

  @override
  AddCourseTileContent courseToTileContent(PublicCoursesChunk course) =>
      PreviewAddCourseTileContent(course);

  @override
  void onSelect(PublicCoursesChunk course, BuildContext context) {
    final lang = targetLanguageFilter.value?.langCode;
    context.go(
      WorkspaceNav.openAddCoursePage(
        GoRouterState.of(context).uri,
        AddCourseSubpageEnum.browse,
        previewRoomId: course.room.roomId,
        initialLanguageFilter: lang,
        allLanguagesFilter: lang == null,
      ),
    );
  }

  @override
  void onNotFound(BuildContext context) {
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
  Future<void> fetchAndAppend(int generation) async {
    // Measured before anything is shown, so courses surfaced from the cache
    // count as progress for this load rather than triggering further round
    // trips for results the user can already see.
    final int startingCount = loadedCourses.length;

    // First, get any courses from the cache that should be visible and show
    setLoadedCourses([...loadedCourses, ..._coursesToAdd]);
    setFilteredCourses(AsyncLoaded(filteredCourses));

    int batches = 0;
    while (loadGeneration == generation &&
        loadingMore.value &&
        !fullyLoaded &&
        batches < _maxBatchesPerLoad &&
        loadedCourses.length - startingCount < _pageTarget) {
      await _loadNextBatch();
      if (disposed || loadGeneration != generation) return;
      setLoadedCourses([...loadedCourses, ..._coursesToAdd]);
      setFilteredCourses(AsyncLoaded(filteredCourses));
      batches++;
    }
  }

  /// Load and cache the next 10 public courses and course plans if applicable
  Future<void> _loadNextBatch() async {
    if (fullyLoaded) return;
    final coursesResult = await _requestPublicCourses();
    if (coursesResult.isError) {
      loadingMore.value = false;
      return;
    }

    final coursesResp = coursesResult.result!;
    _nextBatch = coursesResp.nextBatch;
    if (_nextBatch == null) {
      setFullyLoaded(true);
    }

    for (final course in coursesResp.courses) {
      if (!_resultsCache.any((c) => c.room.roomId == course.room.roomId)) {
        _resultsCache.add(course);
      }
    }

    final undiscoveredCourseIds = coursesResp.courses
        .where((c) => !_coursePlans.containsKey(c.courseId))
        .map((c) => c.courseId)
        .toSet()
        .toList();

    final coursePlansResult = await _requestCoursePlans(undiscoveredCourseIds);
    if (coursePlansResult.isError) {
      loadingMore.value = false;
      return;
    }

    final searchResult = coursePlansResult.result!;
    for (final entry in searchResult.entries) {
      _coursePlans[entry.key] = entry.value;
    }
  }

  Future<Result<PublicCoursesResponse>> _requestPublicCourses() async {
    try {
      final targetLanguage = targetLanguageFilter.value?.langCodeShort;
      final resp = await client.requestPublicCourses(
        since: _nextBatch,
        targetLanguage: targetLanguage?.isNotEmpty == true
            ? targetLanguage
            : null,
      );
      return Result.value(resp);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'nextBatch': _nextBatch});
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
}
