import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/join_room_analytics_consent_handler.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/web_search_focus_keeper.dart';
import 'package:fluffychat/pangea/common/widgets/filter_pill_row.dart';
import 'package:fluffychat/pangea/spaces/client_spaces_extension.dart';
import 'package:fluffychat/pangea/spaces/course_role_filter.dart';
import 'package:fluffychat/pangea/spaces/course_search.dart';
import 'package:fluffychat/routes/courses/add_course_options.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';
import 'package:fluffychat/routes/courses/add_course_tile_list.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/panel_header.dart';
import 'package:fluffychat/utils/chat_list_handle_space_tap.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/pangea_search_bar.dart';

/// The **Courses** left-column panel (world_v2): the "Courses" header plus the
/// scrollable list of joined courses.
///
/// The three add-course actions (start my own / enter a code / browse public)
/// live in the header as compact right-justified icons once the learner has at
/// least one course — so the list gets the vertical space — and drop to
/// full-width buttons in the body as the empty state when the learner is in no
/// courses yet. The panel host ([WorkspaceLeftPanel]) supplies the surrounding
/// card chrome (or, on narrow, the nav-widget cavity). See routing.instructions.md.
class CoursesHubPanel extends StatelessWidget {
  final Widget closeButton;

  const CoursesHubPanel({super.key, required this.closeButton});

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final l10n = L10n.of(context);

    // The panel's one named group comes from the dispatcher (#8729).
    return StreamBuilder(
      stream: client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 1)),
      builder: (context, _) {
        final courses = client.sortedCourses(l10n);
        return Column(
          children: [
            PanelHeader(
              leading: closeButton,
              title: l10n.courses,
              // With courses present, the three add-course actions ride the
              // header as right-justified icons; when empty they stay as full
              // buttons in the body below (the empty state).
              trailing: courses.isEmpty ? null : const AddCourseHeaderActions(),
            ),
            Expanded(child: LeftPanelCoursesListView(courses: courses)),
          ],
        );
      },
    );
  }
}

/// The scrollable body of [CoursesHubPanel]: a tile per invited or joined
/// course (matching nav rail behavior on course selection), and — only when the
/// learner has none yet — the "Add new course" divider and the full-width
/// add-course buttons as the empty state (#7172).
///
/// Above the tiles: a search bar once the learner has joined more than
/// [maxJoinedCoursesWithoutSearch] courses, and the role filter pills when
/// they both teach and learn (#9207). Both narrow the one activity-ordered
/// list; neither survives the panel closing.
class LeftPanelCoursesListView extends StatefulWidget {
  static const int maxJoinedCoursesWithoutSearch = 4;

  final List<Room> courses;

  const LeftPanelCoursesListView({super.key, required this.courses});

  static bool showsSearchBar(Iterable<Room> courses) =>
      courses.where((c) => c.membership == Membership.join).length >
      maxJoinedCoursesWithoutSearch;

  @override
  State<LeftPanelCoursesListView> createState() =>
      _LeftPanelCoursesListViewState();
}

class _LeftPanelCoursesListViewState extends State<LeftPanelCoursesListView> {
  final ValueNotifier<CourseRoleFilter> _roleFilter = ValueNotifier(
    CourseRoleFilter.all,
  );
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final WebSearchFocusKeeper _searchFocusKeeper = WebSearchFocusKeeper(
    focusNode: _searchFocusNode,
    isSearchOpen: () =>
        mounted && LeftPanelCoursesListView.showsSearchBar(widget.courses),
  );

  /// Each searchable course's CEFR level by course room id, for matching the
  /// level its tile shows. Read from the same per-course quest outline the
  /// tile's chips read, so matching can't disagree with what is on screen.
  final ValueNotifier<Map<String, LanguageLevelTypeEnum>> _levels =
      ValueNotifier(const {});

  /// The quest uuid per course room the current [_levels] load was for.
  Map<String, String> _levelQuestIds = const {};

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChange);
    _loadLevels();
  }

  @override
  void didUpdateWidget(covariant LeftPanelCoursesListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadLevels();
  }

  @override
  void dispose() {
    _searchFocusKeeper.disarm();
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _searchFocusNode.dispose();
    _searchController.dispose();
    _roleFilter.dispose();
    _levels.dispose();
    super.dispose();
  }

  /// The search bar is always on screen, so the keeper arms whenever the
  /// learner puts focus in it; a pointer-down anywhere disarms it again.
  void _onSearchFocusChange() {
    if (_searchFocusNode.hasFocus) _searchFocusKeeper.arm();
  }

  /// Clearing keeps the learner searching: the clear button's pointer-down
  /// disarmed the keeper, but the tiles all coming back is exactly the churn
  /// that drops the field's focus.
  void _clearSearch() {
    _searchController.clear();
    if (_searchFocusNode.hasFocus) _searchFocusKeeper.arm();
  }

  /// Resolves [_levels] whenever the searchable course set changes. The
  /// outlines are normally cached already — the world map's joined-course
  /// cache and the tiles' own chips read the same ones.
  Future<void> _loadLevels() async {
    final questIds = {
      if (LeftPanelCoursesListView.showsSearchBar(widget.courses))
        for (final course in widget.courses)
          if (course.membership == Membership.join && course.coursePlan != null)
            course.id: course.coursePlan!.uuid,
    };
    if (mapEquals(questIds, _levelQuestIds)) return;
    _levelQuestIds = questIds;

    final outlines = await Future.wait(
      questIds.entries.map(
        (entry) => QuestRepo.outline(entry.value, courseRoomId: entry.key),
      ),
    );
    if (!mounted || !mapEquals(questIds, _levelQuestIds)) return;
    // A failed read is already logged by the repo; that course's tile shows no
    // level chip either, so there is no level to match.
    _levels.value = {
      for (final (index, roomId) in questIds.keys.indexed)
        if (outlines[index].result case final outline?)
          roomId: outline.quest.cefrLevel,
    };
  }

  CourseSearchText _searchTextOf(Room course) => CourseSearchText(
    title: course.getLocalizedDisplayname(),
    description: course.topic,
    level: _levels.value[course.id]?.title(context),
  );

  /// Open joined courses, or open popup for invited courses
  Future<void> onTapCourse(BuildContext context, Room course) async {
    final uri = GoRouterState.of(context).uri;
    final membership = course.membership;

    if (!{Membership.invite, Membership.leave}.contains(membership)) {
      context.go(
        // No section param even for a knock-badged course: knocks surface in
        // the Catch up card at the top of the page (#8357), which a
        // scroll-to-Chats would skip right past.
        WorkspaceNav.openCourseSection(uri, course.id, keepRoom: false),
      );
      return;
    }

    final joinResp = course.membership == Membership.invite
        ? await SpaceTapUtil.onInviteTap(context, course)
        : await SpaceTapUtil.autoJoin(context, course);

    if (joinResp == null) return;
    final joinedRoom = course.client.getRoomById(joinResp.roomId);
    if (joinedRoom == null) return;

    final handler = JoinRoomAnalyticsConsentHandler(joinResp, joinedRoom);
    final joinedRoomId = await handler.handle(context);
    if (joinedRoomId == null) return;

    context.go(
      WorkspaceNav.openCourseSection(uri, joinedRoomId, keepRoom: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final allCourses = widget.courses;
    final showsSearchBar = LeftPanelCoursesListView.showsSearchBar(allCourses);
    final showsRoleFilter = CourseRoleFilter.appliesTo(allCourses);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Column(
        children: [
          if (showsSearchBar)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: ValueListenableBuilder(
                valueListenable: _searchController,
                builder: (context, query, _) => PangeaSearchBar(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  labelText: l10n.searchCoursesHint,
                  suffixIcon: query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: l10n.clearSearch,
                          icon: const Icon(Icons.close_outlined),
                          onPressed: _clearSearch,
                        ),
                ),
              ),
            ),
          if (showsRoleFilter)
            ValueListenableBuilder(
              valueListenable: _roleFilter,
              builder: (context, selected, _) => FilterPillRow(
                semanticsLabel: l10n.courseListFiltersLabel,
                filters: CourseRoleFilter.values,
                selected: selected,
                onSelected: (filter) => _roleFilter.value = filter,
                labelOf: (filter) => filter.label(l10n),
                tooltipOf: (filter) => filter.tooltip(l10n),
                padding: const EdgeInsets.only(bottom: 8.0),
              ),
            ),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                _roleFilter,
                _searchController,
                _levels,
              ]),
              builder: (context, _) {
                // A filter or query left over from before the pills or the
                // search bar disappeared (a course was left) no longer applies.
                final roleFilter = showsRoleFilter
                    ? _roleFilter.value
                    : CourseRoleFilter.all;
                final filtered = allCourses.where(roleFilter.includes).toList();
                final courses = showsSearchBar
                    ? CourseSearchText.rank(
                        filtered,
                        _searchController.text,
                        _searchTextOf,
                      )
                    : filtered;

                if (courses.isEmpty && allCourses.isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      l10n.noCoursesMatchSearch,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }

                return Semantics(
                  label: l10n.joinedCourseListLabel,
                  container: true,
                  child: AddCourseTileList(
                    content: courses
                        .map((c) => RoomAddCourseTileContent(c))
                        .toList(),
                    onTap: (index) => onTapCourse(context, courses[index]),
                    extraContent: allCourses.isEmpty
                        ? [
                            const SizedBox(height: 4.0),
                            // "Add new course" section divider + the full
                            // add-course buttons.
                            Row(
                              children: [
                                Expanded(
                                  child: Divider(
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12.0,
                                  ),
                                  child: Text(
                                    l10n.addNewCourse,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Divider(
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12.0),
                            const AddCourseOptions(),
                          ]
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
