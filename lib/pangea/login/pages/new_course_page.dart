import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/url_image_widget.dart';
import 'package:fluffychat/pangea/course_creation/course_info_chip_widget.dart';
import 'package:fluffychat/pangea/course_creation/course_language_filter.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_filter.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_client_extension.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plans_repo.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/languages/p_language_store.dart';
import 'package:fluffychat/pangea/learning_settings/language_level_type_enum.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class NewCoursePage extends StatefulWidget {
  final String route;
  final String? spaceId;
  final bool showFilters;
  final String? initialLanguageCode;
  final bool showAll;

  const NewCoursePage({
    super.key,
    required this.route,
    this.spaceId,
    this.showFilters = true,
    this.initialLanguageCode,
    this.showAll = false,
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
      if (widget.initialLanguageCode != null) {
        _targetLanguageFilter.value = PLanguageStore.byLangCode(
          widget.initialLanguageCode!,
        );
      }

      if (_targetLanguageFilter.value == null) {
        _targetLanguageFilter.value =
            MatrixState.pangeaController.userController.userL2;
      }
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
    _scrollController.jumpTo(0);
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
      final resp = await CoursePlansRepo.searchByFilter(
        filter: _filter,
        page: _currentPage,
      );
      if (!mounted || _loadGeneration != generation) return;
      final sortedCoursePlans = resp.coursePlans.values.toList().sorted(
        (a, b) => LanguageLevelTypeEnum.values
            .indexOf(a.cefrLevel)
            .compareTo(LanguageLevelTypeEnum.values.indexOf(b.cefrLevel)),
      );
      _accumulatedCourses = [..._accumulatedCourses, ...sortedCoursePlans];
      _fullyLoaded = !resp.hasNextPage;
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

    if (existingRoom == null || widget.spaceId != null) {
      context.go(
        widget.spaceId != null
            ? '/rooms/spaces/${widget.spaceId}/addcourse/${course.uuid}'
            : '/${widget.route}/course/own/${course.uuid}',
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
        widget.spaceId != null
            ? '/rooms/spaces/${widget.spaceId}/addcourse/${course.uuid}'
            : '/${widget.route}/course/own/${course.uuid}',
      );
    } else if (action == 1) {
      if (existingRoom.isSpace) {
        context.go('/rooms/spaces/${existingRoom.id}');
      } else {
        ErrorHandler.logError(
          e: "Existing course room is not a space",
          data: {'roomId': existingRoom.id, 'courseId': course.uuid},
        );
        context.go('/rooms/${existingRoom.id}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spaceId = widget.spaceId;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          spaceId != null
              ? L10n.of(context).addCoursePlan
              : L10n.of(context).startOwn,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(20.0),
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
                                        onPressed: () => context.go('/rooms'),
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
                                  child: Column(
                                    spacing: 4.0,
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        spacing: 8.0,
                                        children: [
                                          SizedBox(
                                            width: 58.0,
                                            height: 58.0,
                                            child: ImageByUrl(
                                              imageUrl: course.imageUrl,
                                              width: 58.0,
                                              borderRadius:
                                                  BorderRadius.circular(10.0),
                                              replacement: Avatar(
                                                name: course.title,
                                                borderRadius:
                                                    BorderRadius.circular(10.0),
                                                size: 58.0,
                                              ),
                                            ),
                                          ),
                                          Flexible(
                                            child: Text(
                                              course.title,
                                              style: theme.textTheme.bodyLarge,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      CourseInfoChips(
                                        course.uuid,
                                        iconSize: 12.0,
                                        fontSize: 12.0,
                                      ),
                                      Text(
                                        course.description,
                                        style: theme.textTheme.bodyMedium,
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
