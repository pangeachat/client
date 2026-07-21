import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/courses/add_course_error_message.dart';
import 'package:fluffychat/routes/courses/add_course_tile_list.dart';
import 'package:fluffychat/routes/courses/course_language_filter.dart';
import 'package:fluffychat/routes/courses/course_search_controller.dart';

class CourseSearchView<T> extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? closeButton;
  final String notFoundMessage;
  final String notFoundButtonLabel;
  final String hintText;
  final CourseSearchController courseSearch;
  const CourseSearchView({
    super.key,
    required this.title,
    required this.actions,
    required this.closeButton,
    required this.notFoundMessage,
    required this.notFoundButtonLabel,
    required this.hintText,
    required this.courseSearch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: closeButton,
        title: Text(
          title,
          style: FluffyThemes.isColumnMode(context)
              ? theme.textTheme.titleLarge
              : theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
        ),
        centerTitle: false,
        titleSpacing: 0,
        actions: actions,
      ),
      body: SafeArea(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Column(
              spacing: 20.0,
              children: [
                ValueListenableBuilder(
                  valueListenable: courseSearch.searchingNotifier,
                  builder: (context, searching, _) => Row(
                    spacing: 4.0,
                    children: [
                      Expanded(
                        child: searching
                            ? TextField(
                                controller: courseSearch.searchController,
                                decoration: InputDecoration(hintText: hintText),
                                focusNode: courseSearch.focusNode,
                              )
                            : ValueListenableBuilder(
                                valueListenable:
                                    courseSearch.targetLanguageFilter,
                                builder: (context, value, _) {
                                  return CourseLanguageFilter(
                                    value:
                                        courseSearch.targetLanguageFilter.value,
                                    onChanged:
                                        courseSearch.setTargetLanguageFilter,
                                  );
                                },
                              ),
                      ),
                      IconButton(
                        icon: Icon(searching ? Icons.close : Icons.search),
                        onPressed: searching
                            ? courseSearch.stopSearching
                            : courseSearch.startSearching,
                      ),
                    ],
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: courseSearch.filteredCoursesLoader,
                  builder: (context, state, _) {
                    switch (state) {
                      case AsyncLoading():
                      case AsyncIdle():
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32.0),
                            child: CircularProgressIndicator.adaptive(),
                          ),
                        );
                      case AsyncError():
                        return AddCourseErrorMessage(
                          message: L10n.of(context).oopsSomethingWentWrong,
                          buttonLabel: L10n.of(context).tryAgain,
                          onPressed: courseSearch.loadCourses,
                        );
                      case AsyncLoaded(value: final courses):
                        return ValueListenableBuilder(
                          valueListenable: courseSearch.loadingMore,
                          builder: (context, isLoadingMore, _) {
                            if (courses.isEmpty &&
                                !isLoadingMore &&
                                courseSearch.fullyLoaded) {
                              return AddCourseErrorMessage(
                                message: notFoundMessage,
                                buttonLabel: notFoundButtonLabel,
                                onPressed: () =>
                                    courseSearch.onNotFound(context),
                              );
                            }

                            final loadingIndicator =
                                !isLoadingMore && courseSearch.fullyLoaded
                                ? SizedBox.shrink()
                                : SizedBox(
                                    height: 60,
                                    child: Center(
                                      child: isLoadingMore
                                          ? const CircularProgressIndicator.adaptive()
                                          : !courseSearch.fullyLoaded
                                          ? TextButton(
                                              onPressed: courseSearch.loadMore,
                                              child: Text(
                                                L10n.of(context).loadMore,
                                              ),
                                            )
                                          : const SizedBox(),
                                    ),
                                  );

                            return Expanded(
                              child: AddCourseTileList(
                                content: courses
                                    .map(courseSearch.courseToTileContent)
                                    .toList(),
                                onTap: (index) => courseSearch.onSelect(
                                  courses[index],
                                  context,
                                ),
                                extraContent: [loadingIndicator],
                                controller: courseSearch.scrollController,
                              ),
                            );
                          },
                        );
                    }
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
