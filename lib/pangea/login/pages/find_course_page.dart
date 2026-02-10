import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/common/widgets/url_image_widget.dart';
import 'package:fluffychat/pangea/course_creation/course_info_chip_widget.dart';
import 'package:fluffychat/pangea/course_creation/course_language_filter.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plans_repo.dart';
import 'package:fluffychat/pangea/course_plans/courses/get_localized_courses_request.dart';
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/pangea/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/spaces/public_course_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';

class FindCoursePage extends StatefulWidget {
  const FindCoursePage({super.key});

  @override
  State<FindCoursePage> createState() => FindCoursePageState();
}

class FindCoursePageState extends State<FindCoursePage> {
  final TextEditingController searchController = TextEditingController();

  bool loading = true;
  bool _fullyLoaded = false;
  Object? error;
  Timer? _coolDown;

  LanguageModel? targetLanguageFilter;

  List<PublicCoursesChunk> discoveredCourses = [];
  Map<String, CoursePlanModel> coursePlans = {};
  String? nextBatch;

  @override
  void initState() {
    super.initState();

    final target = MatrixState.pangeaController.userController.userL2;
    if (target != null) {
      setTargetLanguageFilter(target);
    }

    _loadCourses();
  }

  @override
  void dispose() {
    searchController.dispose();
    _coolDown?.cancel();
    super.dispose();
  }

  void setTargetLanguageFilter(LanguageModel? language) {
    if (targetLanguageFilter?.langCodeShort == language?.langCodeShort) return;
    setState(() => targetLanguageFilter = language);
    _loadCourses();
  }

  void onSearchEnter(String text, {bool globalSearch = true}) {
    if (text.isEmpty) {
      _loadCourses();
      return;
    }

    _coolDown?.cancel();
    _coolDown = Timer(const Duration(milliseconds: 500), _loadCourses);
  }

  List<PublicCoursesChunk> get filteredCourses {
    List<PublicCoursesChunk> filtered = discoveredCourses
        .where(
          (c) =>
              !Matrix.of(context).client.rooms.any(
                (r) => r.id == c.room.roomId && r.membership == Membership.join,
              ) &&
              coursePlans.containsKey(c.courseId),
        )
        .toList();

    if (targetLanguageFilter != null) {
      filtered = filtered.where((chunk) {
        final course = coursePlans[chunk.courseId];
        if (course == null) return false;
        return course.targetLanguage.split('-').first ==
            targetLanguageFilter!.langCodeShort;
      }).toList();
    }

    final searchText = searchController.text.trim().toLowerCase();
    if (searchText.isNotEmpty) {
      filtered = filtered.where((chunk) {
        final course = coursePlans[chunk.courseId];
        if (course == null) return false;
        final name = chunk.room.name?.toLowerCase() ?? '';
        final description = course.description.toLowerCase();
        return name.contains(searchText) || description.contains(searchText);
      }).toList();
    }

    // sort by join rule, with knock rooms at the end
    filtered.sort((a, b) {
      final aKnock = a.room.joinRule == JoinRules.knock.name;
      final bKnock = b.room.joinRule == JoinRules.knock.name;
      if (aKnock && !bKnock) return 1;
      if (!aKnock && bKnock) return -1;
      return 0;
    });

    return filtered;
  }

  Future<void> _loadPublicSpaces() async {
    try {
      final resp = await Matrix.of(
        context,
      ).client.requestPublicCourses(since: nextBatch);

      for (final room in resp.courses) {
        if (!discoveredCourses.any((e) => e.room.roomId == room.room.roomId)) {
          discoveredCourses.add(room);
        }
      }

      nextBatch = resp.nextBatch;
    } catch (e, s) {
      error = e;
      ErrorHandler.logError(e: e, s: s, data: {'nextBatch': nextBatch});
    }
  }

  Future<void> _loadCourses() async {
    if (_fullyLoaded && nextBatch == null) {
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    await _loadPublicSpaces();

    int timesLoaded = 0;
    while (error == null && timesLoaded < 5 && nextBatch != null) {
      await _loadPublicSpaces();
      timesLoaded++;
    }

    if (nextBatch == null) {
      _fullyLoaded = true;
    }

    try {
      final resp = await CoursePlansRepo.search(
        GetLocalizedCoursesRequest(
          coursePlanIds: discoveredCourses
              .map((c) => c.courseId)
              .toSet()
              .toList(),
          l1: MatrixState.pangeaController.userController.userL1Code!,
        ),
      );
      final searchResult = resp.coursePlans;

      coursePlans.clear();
      for (final entry in searchResult.entries) {
        coursePlans[entry.key] = entry.value;
      }
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'discoveredCourses': discoveredCourses
              .map((c) => c.courseId)
              .toList(),
        },
      );
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  void startNewCourse() {
    String route = "/rooms/course/own";
    if (targetLanguageFilter != null) {
      route +=
          "?lang=${Uri.encodeComponent(targetLanguageFilter!.langCodeShort)}";
    }
    context.go(route);
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
    final isColumnMode = FluffyThemes.isColumnMode(context);

    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).findCourse)),
      body: MaxWidthBody(
        showBorder: false,
        withScrolling: false,
        maxWidth: 600.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            spacing: 16.0,
            children: [
              InstructionsInlineTooltip(
                instructionsEnum: InstructionsEnum.courseDescription,
              ),
              TextField(
                controller: controller.searchController,
                textInputAction: TextInputAction.search,
                onChanged: controller.onSearchEnter,
                decoration: InputDecoration(
                  filled: !isColumnMode,
                  fillColor: isColumnMode
                      ? null
                      : theme.colorScheme.secondaryContainer,
                  border: OutlineInputBorder(
                    borderSide: isColumnMode
                        ? const BorderSide()
                        : BorderSide.none,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  contentPadding: const EdgeInsets.fromLTRB(0, 0, 20.0, 0),
                  hintText: L10n.of(context).findCourse,
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.normal,
                    fontSize: 16.0,
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  prefixIcon: IconButton(
                    onPressed: () {},
                    icon: Icon(
                      Icons.search_outlined,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              LayoutBuilder(
                builder: (context, constrained) {
                  return Row(
                    spacing: 12.0,
                    children: [
                      Expanded(
                        child: CourseLanguageFilter(
                          value: controller.targetLanguageFilter,
                          onChanged: controller.setTargetLanguageFilter,
                        ),
                      ),
                      if (constrained.maxWidth >= 500) ...[
                        TextButton(
                          onPressed: controller.startNewCourse,
                          child: Row(
                            spacing: 8.0,
                            children: [
                              const Icon(Icons.add),
                              Text(L10n.of(context).newCourse),
                            ],
                          ),
                        ),
                        TextButton(
                          child: Row(
                            spacing: 8.0,
                            children: [
                              const Icon(Icons.join_full),
                              Text(L10n.of(context).joinWithCode),
                            ],
                          ),
                          onPressed: () => context.go("/rooms/course/private"),
                        ),
                      ] else
                        PopupMenuButton(
                          icon: const Icon(Icons.more_vert),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              onTap: controller.startNewCourse,
                              child: Row(
                                spacing: 8.0,
                                children: [
                                  const Icon(Icons.add),
                                  Text(L10n.of(context).newCourse),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              onTap: () => context.go("/rooms/course/private"),
                              child: Row(
                                spacing: 8.0,
                                children: [
                                  const Icon(Icons.join_full),
                                  Text(L10n.of(context).joinWithCode),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  );
                },
              ),
              ValueListenableBuilder(
                valueListenable: controller.searchController,
                builder: (context, _, _) {
                  if (controller.error != null) {
                    return ErrorIndicator(
                      message: L10n.of(context).oopsSomethingWentWrong,
                    );
                  }

                  if (controller.loading) {
                    return const CircularProgressIndicator.adaptive();
                  }

                  if (controller.filteredCourses.isEmpty) {
                    return Text(L10n.of(context).nothingFound);
                  }

                  return Expanded(
                    child: ListView.builder(
                      itemCount: controller.filteredCourses.length,
                      itemBuilder: (context, index) {
                        final space = controller.filteredCourses[index];
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
    context.go('/rooms/course/${Uri.encodeComponent(chunk.room.roomId)}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final space = chunk.room;
    final courseId = chunk.courseId;
    final displayname =
        space.name ?? space.canonicalAlias ?? L10n.of(context).emptyChat;

    return Padding(
      padding: isColumnMode
          ? const EdgeInsets.only(bottom: 32.0)
          : const EdgeInsets.only(bottom: 16.0),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _navigateToCoursePage(context),
          borderRadius: BorderRadius.circular(12.0),
          child: Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: theme.colorScheme.primary),
            ),
            child: Column(
              spacing: 4.0,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  spacing: 8.0,
                  children: [
                    ImageByUrl(
                      imageUrl: space.avatarUrl,
                      width: 58.0,
                      borderRadius: BorderRadius.circular(10.0),
                      replacement: Avatar(
                        name: displayname,
                        borderRadius: BorderRadius.circular(10.0),
                        size: 58.0,
                      ),
                    ),
                    Flexible(
                      child: Column(
                        spacing: 0.0,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayname,
                            style: theme.textTheme.bodyLarge,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Row(
                            spacing: 4.0,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.group, size: 16.0),
                              Text(
                                L10n.of(
                                  context,
                                ).countParticipants(space.numJoinedMembers),
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (course != null) ...[
                  CourseInfoChips(courseId, iconSize: 12.0, fontSize: 12.0),
                  Text(course!.description, style: theme.textTheme.bodyMedium),
                ],
                const SizedBox(height: 12.0),
                HoverBuilder(
                  builder: (context, hovered) => ElevatedButton(
                    onPressed: () => _navigateToCoursePage(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primaryContainer
                          .withAlpha(hovered ? 255 : 200),
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          space.joinRule == JoinRules.knock.name
                              ? L10n.of(context).knock
                              : L10n.of(context).join,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
