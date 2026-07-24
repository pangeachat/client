import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/courses/add_course_error_message.dart';
import 'package:fluffychat/routes/courses/add_course_tile_list.dart';
import 'package:fluffychat/routes/courses/course_language_filter.dart';
import 'package:fluffychat/routes/courses/course_search_controller.dart';
import 'package:fluffychat/widgets/pangea_search_bar.dart';

class CourseSearchView<T> extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? closeButton;
  final String notFoundMessage;
  final String notFoundButtonLabel;
  final String labelText;
  final CourseSearchController<T> courseSearch;
  const CourseSearchView({
    super.key,
    required this.title,
    required this.actions,
    required this.closeButton,
    required this.notFoundMessage,
    required this.notFoundButtonLabel,
    required this.labelText,
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
      body: Center(
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
                          ? PangeaSearchBar(
                              controller: courseSearch.searchController,
                              labelText: labelText,
                              focusNode: courseSearch.focusNode,
                              suffixIcon: IconButton(
                                icon: Icon(Icons.close),
                                tooltip: L10n.of(context).closeSearch,
                                onPressed: courseSearch.stopSearching,
                              ),
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
                    if (!searching)
                      IconButton(
                        icon: Icon(Icons.search),
                        tooltip: L10n.of(context).search,
                        onPressed: courseSearch.startSearching,
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
                        onPressed: courseSearch.loadMore,
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
                              onPressed: () => courseSearch.onNotFound(context),
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
    );
  }
}
