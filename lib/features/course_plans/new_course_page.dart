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
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/repo/quest_plans_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';
import 'package:fluffychat/routes/courses/course_language_filter.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/url_image_widget.dart';

class NewCoursePage extends StatefulWidget {
  final String route;
  final String? spaceId;
  final bool showFilters;
  final String? initialLanguageCode;
  final bool showAll;

  /// world_v2: when this page is the change-course step hosted inside an
  /// existing course panel (a `course:addcourse` push, `spaceId != null`), the
  /// panel supplies its leading `←` back to the card — the route-driven
  /// add-to-space context otherwise has no back. See `routing.instructions.md`.
  final Widget? embeddedCloseButton;

  const NewCoursePage({
    super.key,
    required this.route,
    this.spaceId,
    this.showFilters = true,
    this.initialLanguageCode,
    this.showAll = false,
    this.embeddedCloseButton,
  });

  @override
  State<NewCoursePage> createState() => NewCoursePageState();
}

class NewCoursePageState extends State<NewCoursePage> {
  /// Session-scoped memory of the last language the learner picked in this flow.
  /// The back arrow returns to the add-course hub via `setSection`, which carries
  /// only the panel/map state forward and drops the `?lang=` query — so without
  /// this, returning to "Start my own" snapped back to the L2 default and lost
  /// the choice (#7269). A `?lang=` deep link still wins; this only fills the
  /// in-session default the hub round-trip would otherwise drop.
  static LanguageModel? _lastChosenLanguage;

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
      _targetLanguageFilter.value = seedLanguage(
        fromInitialCode: widget.initialLanguageCode != null
            ? PLanguageStore.byLangCode(widget.initialLanguageCode!)
            : null,
        lastChosen: _lastChosenLanguage,
        userL2: MatrixState.pangeaController.userController.userL2,
      );
    }

    _loadCourses();
  }

  /// The language the picker opens on: a `?lang=` deep link
  /// ([fromInitialCode]) wins, then this session's last pick ([lastChosen], so
  /// the back-arrow round-trip keeps it), then the learner's L2 default (#7269).
  @visibleForTesting
  static LanguageModel? seedLanguage({
    required LanguageModel? fromInitialCode,
    required LanguageModel? lastChosen,
    required LanguageModel? userL2,
  }) => fromInitialCode ?? lastChosen ?? userL2;

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
    _lastChosenLanguage =
        language; // remember for the rest of this session (#7269)
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
        '/courses/${shortRoomId(widget.spaceId!)}/addcourse/${course.uuid}',
      );
      return;
    }

    if (existingRoom == null) {
      context.go(
        WorkspaceNav.openAddCourse(
          GoRouterState.of(context).uri,
          subpage: 'own',
          courseId: course.uuid,
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
      context.go(
        WorkspaceNav.openAddCourse(
          GoRouterState.of(context).uri,
          subpage: 'own',
          courseId: course.uuid,
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
        leading: spaceId == null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                // Accessible name (world_v2 testability contract: every
                // IconButton needs a tooltip → semantics label).
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                // world_v2: the add-course hub is the `addcourse` left token over
                // the world map, not a `/courses` route.
                onPressed: () => context.go(
                  WorkspaceNav.setSection(
                    GoRouterState.of(context).uri,
                    const PanelToken('addcourse'),
                    keepRoom: false,
                  ),
                ),
              )
            : widget.embeddedCloseButton,
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
            constraints: const BoxConstraints(maxWidth: 450),
            child: Column(
              children: [
                if (widget.showFilters) ...[
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
                ],
                ValueListenableBuilder(
                  valueListenable: _courses,
                  builder: (context, value, _) {
                    final loading = value == null;
                    if (loading || value.isError || value.result!.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: loading
                              ? const CircularProgressIndicator.adaptive()
                              : Center(
                                  child: Column(
                                    spacing: 12.0,
                                    children: [
                                      const BotFace(
                                        expression: BotExpression.addled,
                                        width: Avatar.defaultSize * 1.5,
                                      ),
                                      Text(
                                        L10n.of(context).noCourseTemplatesFound,
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.bodyLarge,
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            context.go(PRoutes.chatsList),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: theme
                                              .colorScheme
                                              .primaryContainer,
                                          foregroundColor: theme
                                              .colorScheme
                                              .onPrimaryContainer,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(L10n.of(context).continueText),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      );
                    }

                    final courses = value.result!;
                    return Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: courses.length + 1,
                        itemBuilder: (context, index) {
                          if (index == courses.length) {
                            return ValueListenableBuilder(
                              valueListenable: _loadingMore,
                              builder: (context, isLoadingMore, _) {
                                if (!isLoadingMore && _fullyLoaded) {
                                  return const SizedBox.shrink();
                                }
                                return SizedBox(
                                  height:
                                      60, // 👈 KEY: fixed height prevents jump
                                  child: Center(
                                    child: isLoadingMore
                                        ? const CircularProgressIndicator.adaptive()
                                        : !_fullyLoaded
                                        ? TextButton(
                                            onPressed: _loadMore,
                                            child: Text(
                                              L10n.of(context).loadMore,
                                            ),
                                          )
                                        : const SizedBox(),
                                  ),
                                );
                              },
                            );
                          }
                          final course = courses[index];
                          // Tapping the card scopes the map to this plan's
                          // activities (world_v2); the Create button starts
                          // the course.
                          return Material(
                            type: MaterialType.transparency,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                              ),
                              child: InkWell(
                                onTap: () => _onSelect(course),
                                borderRadius: BorderRadius.circular(12.0),
                                child: Container(
                                  padding: const EdgeInsets.all(12.0),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12.0),
                                    border: Border.all(
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  child: Row(
                                    spacing: 12.0,
                                    children: [
                                      SizedBox(
                                        width: 48.0,
                                        height: 48.0,
                                        child: ImageByUrl(
                                          imageUrl: course.imageUrl,
                                          width: 48.0,
                                          borderRadius: BorderRadius.circular(
                                            10.0,
                                          ),
                                          replacement: Avatar(
                                            name: course.title,
                                            borderRadius: BorderRadius.circular(
                                              10.0,
                                            ),
                                            size: 48.0,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Column(
                                          spacing: 6.0,
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              course.title,
                                              style: theme.textTheme.bodyLarge,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            CourseInfoChips(
                                              course.uuid,
                                              iconSize: 12.0,
                                              fontSize: 12.0,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
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
      ),
    );
  }
}
