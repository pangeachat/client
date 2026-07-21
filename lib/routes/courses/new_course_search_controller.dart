import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_filter.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_client_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/repo/quest_plans_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';
import 'package:fluffychat/routes/courses/course_search_controller.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';

class NewCourseSearchController
    extends CourseSearchController<CoursePlanModel> {
  final Client client;
  final String? spaceId;

  NewCourseSearchController({required this.client, this.spaceId})
    : super(getCourseName: (c) => c.title);

  int _currentPage = 1;
  List<CoursePlanModel> _accumulatedCourses = [];

  CourseFilter get _filter {
    return CourseFilter(targetLanguage: targetLanguageFilter.value);
  }

  @override
  AddCourseTileContent courseToTileContent(CoursePlanModel course) =>
      CoursePlanAddCourseTileContent(course);

  @override
  void reset() {
    _currentPage = 1;
    _accumulatedCourses = [];
  }

  @override
  void onSelect(CoursePlanModel course, BuildContext context) async {
    final existingRoom = client.getRoomByCourseId(course.uuid);
    final spaceId = this.spaceId;
    if (spaceId != null) {
      context.go(
        WorkspaceNav.openCoursePage(
          GoRouterState.of(context).uri,
          RoomSubpageEnum.addcourse,
          courseId: course.uuid,
          initialLanguageFilter: targetLanguageFilter.value?.langCode,
        ),
      );
      return;
    }

    if (existingRoom == null) {
      final lang = targetLanguageFilter.value?.langCode;
      context.go(
        WorkspaceNav.openAddCoursePage(
          GoRouterState.of(context).uri,
          AddCourseSubpageEnum.own,
          createCourseId: course.uuid,
          initialLanguageFilter: lang,
          allLanguagesFilter: lang == null,
        ),
      );
      return;
    }

    final action = await showAdaptiveDialog<int>(
      barrierDismissible: true,
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 256),
          child: Center(child: Text(course.title, textAlign: TextAlign.center)),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 256, maxHeight: 256),
          child: Text(
            L10n.of(context).alreadyInCourseWithID,
            textAlign: TextAlign.center,
          ),
        ),
        actions: [
          AdaptiveDialogAction(
            onPressed: () => Navigator.of(context).pop(0),
            bigButtons: true,
            child: Text(L10n.of(context).createCourse),
          ),
          AdaptiveDialogAction(
            onPressed: () => Navigator.of(context).pop(1),
            bigButtons: true,
            child: Text(L10n.of(context).goToExistingCourse),
          ),
          AdaptiveDialogAction(
            onPressed: () => Navigator.of(context).pop(null),
            bigButtons: true,
            child: Text(L10n.of(context).cancel),
          ),
        ],
      ),
    );

    if (action == 0) {
      final lang = targetLanguageFilter.value?.langCode;
      context.go(
        WorkspaceNav.openAddCoursePage(
          GoRouterState.of(context).uri,
          AddCourseSubpageEnum.own,
          createCourseId: course.uuid,
          initialLanguageFilter: lang,
          allLanguagesFilter: lang == null,
        ),
      );
    } else if (action == 1) {
      if (existingRoom.isSpace) {
        // world_v2: token nav to the existing course card (sets the map filter +
        // course panel), not the legacy /rooms/spaces path.
        context.go(
          WorkspaceNav.openCourse(
            GoRouterState.of(context).uri,
            existingRoom.id,
          ),
        );
      } else {
        ErrorHandler.logError(
          e: "Existing course room is not a space",
          data: {'roomId': existingRoom.id, 'courseId': course.uuid},
        );
        context.go(
          WorkspaceNav.openRoomById(
            GoRouterState.of(context).uri,
            existingRoom.id,
          ),
        );
      }
    }
  }

  @override
  void onNotFound(BuildContext context) => context.go(PRoutes.chatsList);

  @override
  Future<void> fetchAndAppend(int generation) async {
    try {
      // world_v2: the picker lists v3 quest-plans only — the v1 course-plans
      // collection is retired. [QuestPlansRepo] adapts each quest into a
      // synthesized [CoursePlanModel] so the existing card / chip / detail UI
      // renders it; the quest's uuid is shared with the room's
      // `pangea.course_plan` state event, lighting up the Course Plan tab and
      // world map after creation.
      final questsResp = await QuestPlansRepo.searchByFilter(
        filter: _filter,
        page: _currentPage,
      );
      if (disposed || loadGeneration != generation) return;
      final sorted = questsResp.quests.sorted(
        (a, b) => LanguageLevelTypeEnum.values
            .indexOf(a.cefrLevel)
            .compareTo(LanguageLevelTypeEnum.values.indexOf(b.cefrLevel)),
      );
      _accumulatedCourses = [..._accumulatedCourses, ...sorted];
      setFullyLoaded(!questsResp.hasNextPage);
      _currentPage++;
      setLoadedCourses(_accumulatedCourses);
      setFilteredCourses(AsyncLoaded(filteredCourses));
    } catch (e, s) {
      if (disposed || loadGeneration != generation) return;
      ErrorHandler.logError(e: e, s: s, data: {'filter': _filter.toJson()});
      setFilteredCourses(AsyncError(e));
    }
  }
}
