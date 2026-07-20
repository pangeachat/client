import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/features/course_plans/courses/course_filter.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_client_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/repo/quest_plans_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';
import 'package:fluffychat/routes/courses/add_course_tile_list.dart';
import 'package:fluffychat/routes/courses/course_language_filter.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class NewCoursePage extends StatefulWidget {
  final String? spaceId;
  final String? initialLanguageCode;
  final bool showAll;

  /// world_v2: when this page is the change-course step hosted inside an
  /// existing course panel (a `course:addcourse` push, `spaceId != null`), the
  /// panel supplies its leading `←` back to the card — the route-driven
  /// add-to-space context otherwise has no back. See `routing.instructions.md`.
  final Widget closeButton;

  const NewCoursePage({
    super.key,
    this.spaceId,
    this.initialLanguageCode,
    this.showAll = false,
    required this.closeButton,
  });

  @override
  State<NewCoursePage> createState() => NewCoursePageState();
}

class NewCoursePageState extends State<NewCoursePage> {
  final ValueNotifier<Result<List<CoursePlanModel>>?> _courses = ValueNotifier(
    null,
  );

  final ValueNotifier<LanguageModel?> _targetLanguageFilter = ValueNotifier(
    null,
  );

  final ValueNotifier<bool> _loadingMore = ValueNotifier(false);

  final ScrollController _scrollController = ScrollController();

  int _loadGeneration = 0;
  int _currentPage = 1;
  bool _fullyLoaded = false;
  List<CoursePlanModel> _accumulatedCourses = [];

  @override
  void initState() {
    super.initState();

    if (!widget.showAll) {
      final fromInitialCode = widget.initialLanguageCode != null
          ? PLanguageStore.byLangCode(widget.initialLanguageCode!)
          : null;
      final userL2 = MatrixState.pangeaController.userController.userL2;
      _targetLanguageFilter.value = fromInitialCode ?? userL2;
    }

    _loadCourses();
  }

  @override
  void dispose() {
    _courses.dispose();
    _scrollController.dispose();
    _targetLanguageFilter.dispose();
    _loadingMore.dispose();
    super.dispose();
  }

  CourseFilter get _filter {
    return CourseFilter(targetLanguage: _targetLanguageFilter.value);
  }

  void _setTargetLanguageFilter(LanguageModel? language) {
    if (_targetLanguageFilter.value == language) return;
    _targetLanguageFilter.value = language;
    _loadGeneration++;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    final int generation = _loadGeneration;
    _currentPage = 1;
    _fullyLoaded = false;
    _accumulatedCourses = [];
    _loadingMore.value = false;
    _courses.value = null;
    await _fetchAndAppend(generation);
    if (mounted &&
        _loadGeneration == generation &&
        _courses.value != null &&
        !_courses.value!.isError &&
        _courses.value!.result!.isEmpty) {
      ErrorHandler.logError(
        e: "No courses found",
        data: {'filter': _filter.toJson()},
      );
    }
  }

  Future<void> _loadMore() async {
    if (_fullyLoaded || _loadingMore.value) return;
    final int generation = _loadGeneration;
    _loadingMore.value = true;
    try {
      await _fetchAndAppend(generation);
    } finally {
      if (mounted && _loadGeneration == generation) {
        _loadingMore.value = false;
      }
    }
  }

  Future<void> _fetchAndAppend(int generation) async {
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
      if (!mounted || _loadGeneration != generation) return;
      final sorted = questsResp.quests.sorted(
        (a, b) => LanguageLevelTypeEnum.values
            .indexOf(a.cefrLevel)
            .compareTo(LanguageLevelTypeEnum.values.indexOf(b.cefrLevel)),
      );
      _accumulatedCourses = [..._accumulatedCourses, ...sorted];
      _fullyLoaded = !questsResp.hasNextPage;
      _currentPage++;
      _courses.value = Result.value(_accumulatedCourses);
    } catch (e, s) {
      if (!mounted || _loadGeneration != generation) return;
      ErrorHandler.logError(e: e, s: s, data: {'filter': _filter.toJson()});
      _courses.value = Result.error(e);
    }
  }

  Future<void> _onSelect(CoursePlanModel course) async {
    final existingRoom = Matrix.of(
      context,
    ).client.getRoomByCourseId(course.uuid);

    final spaceId = widget.spaceId;
    if (spaceId != null) {
      context.go(
        WorkspaceNav.openCoursePage(
          GoRouterState.of(context).uri,
          RoomSubpageEnum.addcourse,
          courseId: course.uuid,
          initialLanguageFilter: _targetLanguageFilter.value?.langCode,
        ),
      );
      return;
    }

    if (existingRoom == null) {
      final lang = _targetLanguageFilter.value?.langCode;
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
      final lang = _targetLanguageFilter.value?.langCode;
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spaceId = widget.spaceId;
    return Scaffold(
      appBar: AppBar(
        // In the world_v2 left column the back/close lead back to browse and
        // out to the map; the add-to-space context (a `course:addcourse` push)
        // takes its `←` back-to-card from the host panel.
        leading: widget.closeButton,
        title: Text(
          spaceId != null
              ? L10n.of(context).addCoursePlan
              : L10n.of(context).startOwn,
          style: FluffyThemes.isColumnMode(context)
              ? theme.textTheme.titleLarge
              : theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
        ),
        centerTitle: false,
        titleSpacing: 0,
        actions: spaceId == null
            ? [
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: L10n.of(context).close,
                  onPressed: () => context.go('/'),
                ),
              ]
            : null,
      ),
      body: SafeArea(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        alignment: WrapAlignment.start,
                        children: [
                          ValueListenableBuilder(
                            valueListenable: _targetLanguageFilter,
                            builder: (context, value, _) {
                              return CourseLanguageFilter(
                                value: _targetLanguageFilter.value,
                                onChanged: _setTargetLanguageFilter,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20.0),
                ValueListenableBuilder(
                  valueListenable: _courses,
                  builder: (context, value, _) {
                    if (value == null) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      );
                    }

                    if (value.isError) {
                      return _CoursePickerMessage(
                        message: L10n.of(context).oopsSomethingWentWrong,
                        buttonLabel: L10n.of(context).tryAgain,
                        onPressed: _loadCourses,
                      );
                    }

                    final courses = value.result!;
                    if (courses.isEmpty) {
                      return _CoursePickerMessage(
                        message: L10n.of(context).noCourseTemplatesFound,
                        buttonLabel: L10n.of(context).continueText,
                        onPressed: () => context.go(PRoutes.chatsList),
                      );
                    }

                    final loadingIndicator = ValueListenableBuilder(
                      valueListenable: _loadingMore,
                      builder: (context, isLoadingMore, _) {
                        if (!isLoadingMore && _fullyLoaded) {
                          return const SizedBox.shrink();
                        }
                        return SizedBox(
                          height: 60,
                          child: Center(
                            child: isLoadingMore
                                ? const CircularProgressIndicator.adaptive()
                                : !_fullyLoaded
                                ? TextButton(
                                    onPressed: _loadMore,
                                    child: Text(L10n.of(context).loadMore),
                                  )
                                : const SizedBox(),
                          ),
                        );
                      },
                    );

                    return Expanded(
                      child: AddCourseTileList(
                        content: courses
                            .map((c) => CoursePlanAddCourseTileContent(c))
                            .toList(),
                        onTap: (index) => _onSelect(courses[index]),
                        extraContent: [loadingIndicator],
                        controller: _scrollController,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty- and error-state message for the course picker: an addled bot face, a
/// message, and a single action button. Used for both the "no courses" and the
/// "something went wrong" states, which differ only in copy and action.
class _CoursePickerMessage extends StatelessWidget {
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  const _CoursePickerMessage({
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12.0,
          children: [
            const BotFace(
              expression: BotExpression.addled,
              width: Avatar.defaultSize * 1.5,
            ),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
              ),
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
