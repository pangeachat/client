import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_badge.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_catch_up.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_knock_requests.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_chats_preview.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_participants_preview.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_header.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_link.dart';
import 'package:fluffychat/routes/chat/chat_details/room_details_buttons.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details_content.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_objectives_view.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_progress_bar.dart';
import 'package:fluffychat/widgets/expandable_text.dart';

/// The single scrollable course page (#8357, replacing the tab row): Course
/// plan / Chats / Participants / More as divider-separated sections, each with
/// its highlight inline and a link to its full subpage. The Catch up card
/// (knocks, analytics-access requests, unread rollups) rides at the top and
/// self-hides when empty. A section in the course token's param scrolls the
/// page to that section.
class CourseOverview extends StatefulWidget {
  final SpaceDetailsController controller;
  final Room room;

  /// The More section's rows (admin actions disabled for non-admins).
  final List<ButtonDetails> moreButtons;

  /// Opens the invite flow — the Participants section header's action.
  final VoidCallback onInvite;

  /// The section from the course token to scroll to, or null for the page top.
  final SpaceSettingsTabs? initialSection;

  const CourseOverview({
    required this.controller,
    required this.room,
    required this.moreButtons,
    required this.onInvite,
    this.initialSection,
    super.key,
  });

  @override
  State<CourseOverview> createState() => _CourseOverviewState();
}

class _CourseOverviewState extends State<CourseOverview> {
  final ScrollController _scrollController = ScrollController();

  final Map<SpaceSettingsTabs, GlobalKey> _sectionKeys = {
    SpaceSettingsTabs.course: GlobalKey(),
    SpaceSettingsTabs.chat: GlobalKey(),
    SpaceSettingsTabs.participants: GlobalKey(),
    SpaceSettingsTabs.more: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToSection(widget.initialSection),
    );
  }

  @override
  void didUpdateWidget(covariant CourseOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSection != oldWidget.initialSection) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToSection(widget.initialSection),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSection(SpaceSettingsTabs? section) {
    final sectionContext = _sectionKeys[section]?.currentContext;
    if (sectionContext == null) return;
    Scrollable.ensureVisible(
      sectionContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _openSubpage(SpaceSettingsTabs section) => context.go(
    WorkspaceNav.openCourseTab(
      GoRouterState.of(context).uri,
      tab: section,
      expanded: true,
    ),
  );

  /// Scroll the page from a mouse wheel anywhere over the panel — the gaps
  /// between rows are hit-transparent and this panel floats over the world
  /// map, so an unclaimed wheel would zoom the map instead (the same claim the
  /// full course plan makes — see [CourseObjectivesList]).
  void _claimVerticalScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    if (!_scrollController.hasClients) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      resolved as PointerScrollEvent;
      final position = _scrollController.position;
      final target = (position.pixels + resolved.scrollDelta.dy).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      _scrollController.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final room = widget.room;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: _claimVerticalScroll,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Each section pads itself ([SpaceDetailsContent.sectionPadding])
            // rather than the page, so the dividers between sections run
            // edge-to-edge (#8357 design).
            Padding(
              padding: SpaceDetailsContent.sectionPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The course description leads the page (#8357 review
                  // feedback), with the language/level/module chips directly
                  // below it.
                  if (room.topic.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: ExpandableText(
                        room.topic,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (room.coursePlan != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: CourseInfoChips(
                        room.coursePlan!.uuid,
                        courseRoomId: room.id,
                        fontSize: Theme.of(
                          context,
                        ).textTheme.bodySmall?.fontSize,
                        iconSize: 12.0,
                      ),
                    ),
                  // Pending join requests lead: they are a decision waiting on
                  // the admin, above anything they can merely catch up on.
                  CourseKnockRequests(room: room),
                  CourseCatchUp(room: room),
                  // The course-wide progress bar rides the intro block, under
                  // the attention cards; the Course plan section below starts
                  // straight at its header, with no divider between them.
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: CourseProgressBar(
                      objectivesProvider: widget.controller.objectivesProvider,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: SpaceDetailsContent.sectionPadding,
              child: Column(
                key: _sectionKeys[SpaceSettingsTabs.course],
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CourseSectionHeader(
                    title: SpaceSettingsTabs.course.title(context),
                  ),
                  const SizedBox(height: 8.0),
                  ListenableBuilder(
                    listenable: Listenable.merge([
                      widget.controller.objectivesProvider.questLoader,
                      widget.controller.objectivesProvider.progression,
                      // The course page stashes a ping asynchronously (it
                      // reads the timeline), usually after this first builds.
                      CoursePingBadgeCache.instance,
                    ]),
                    builder: (context, _) {
                      final provider = widget.controller.objectivesProvider;
                      // "See full course plan" only leads somewhere when a
                      // plan can render: hidden when the course has none or
                      // it failed to load (the list shows the error state
                      // alone).
                      final hasPlan = switch (provider.questLoader.value) {
                        AsyncLoaded() =>
                          provider.filteredObjectiveGroups.isNotEmpty,
                        AsyncLoading() => true,
                        AsyncError() || AsyncIdle() => false,
                      };
                      // The Up-next highlight can't show a card pinged in
                      // another Mission, so the link carries the ping badge
                      // to lead the learner into the full plan (#8454), where
                      // the card badge / floating ping-bar take over.
                      final pingLeadsToFullPlan = coursePingLeadsToFullPlan(
                        ping: CoursePingBadgeCache.instance.value,
                        courseId: room.id,
                        planGroups: provider.filteredObjectiveGroups,
                        upNextGroup: provider.upNextGroup,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CourseObjectivesList(
                            room: room,
                            shrinkWrap: true,
                            upNextOnly: true,
                            hasCompletedActivity: (activityId) => widget
                                .controller
                                .roomSummariesModel
                                .hasCompletedActivity(
                                  room.client.userID!,
                                  activityId,
                                ),
                            objectivesProvider:
                                widget.controller.objectivesProvider,
                          ),
                          if (hasPlan)
                            CourseSectionLink(
                              label: l10n.seeFullCoursePlan,
                              onTap: () =>
                                  _openSubpage(SpaceSettingsTabs.course),
                              trailing: pingLeadsToFullPlan
                                  ? const CoursePingBadge()
                                  : null,
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(),
            Column(
              key: _sectionKeys[SpaceSettingsTabs.chat],
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: SpaceDetailsContent.sectionPadding,
                  child: CourseSectionHeader(
                    title: SpaceSettingsTabs.chat.title(context),
                  ),
                ),
                // The chat rows carry their own 8px wrapper (ChatListItem /
                // DefaultChatCreationTile), so the section pads them by the
                // difference — their content then sits at the same inset as
                // every other section.
                Padding(
                  padding:
                      SpaceDetailsContent.sectionPadding -
                      const EdgeInsets.symmetric(horizontal: 8.0),
                  child: CourseChatsPreview(room: room),
                ),
                Padding(
                  padding: SpaceDetailsContent.sectionPadding,
                  child: CourseSectionLink(
                    label: l10n.allChats,
                    onTap: () => _openSubpage(SpaceSettingsTabs.chat),
                  ),
                ),
              ],
            ),
            const Divider(),
            Padding(
              padding: SpaceDetailsContent.sectionPadding,
              child: Column(
                key: _sectionKeys[SpaceSettingsTabs.participants],
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CourseSectionHeader(
                    title: SpaceSettingsTabs.participants.title(context),
                    trailing: room.canInvite
                        ? FilledButton.tonalIcon(
                            onPressed: widget.onInvite,
                            icon: const Icon(
                              Icons.person_add_outlined,
                              size: 16,
                            ),
                            label: Text(
                              l10n.invite,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                        : null,
                  ),
                  CourseParticipantsPreview(room: room),
                  CourseSectionLink(
                    label: l10n.allParticipants,
                    onTap: () => _openSubpage(SpaceSettingsTabs.participants),
                  ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: SpaceDetailsContent.sectionPadding,
              child: Column(
                key: _sectionKeys[SpaceSettingsTabs.more],
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CourseSectionHeader(
                    title: SpaceSettingsTabs.more.title(context),
                  ),
                  _MoreButtonList(buttons: widget.moreButtons),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The More section's rows: every course setting inline (no settings subpage),
/// admin-only rows disabled for non-admins — one layout for all roles.
class _MoreButtonList extends StatelessWidget {
  final List<ButtonDetails> buttons;

  const _MoreButtonList({required this.buttons});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: buttons.where((b) => b.visible).map((b) {
        final title = Text(b.title, style: textTheme.bodyMedium);
        final subtitle = b.description != null
            ? Text(b.description!, style: textTheme.bodySmall)
            : null;
        return Opacity(
          opacity: b.enabled ? 1.0 : 0.5,
          child: b.isToggle
              ? SwitchListTile(
                  title: title,
                  subtitle: subtitle,
                  secondary: b.icon,
                  value: b.value,
                  onChanged: b.enabled ? (value) => b.onPressed?.call() : null,
                  activeThumbColor: AppConfig.activeToggleColor,
                  // The section already carries the page inset, so the tile
                  // keeps just enough of its own to breathe against the
                  // hover surface's edge; compact so the settings read as
                  // one tight list.
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8.0),
                  visualDensity: VisualDensity.compact,
                )
              : ListTile(
                  title: title,
                  subtitle: subtitle,
                  leading: b.icon,
                  onTap: b.enabled ? () => b.onPressed?.call() : null,
                  trailing: b.trailing,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8.0),
                  visualDensity: VisualDensity.compact,
                ),
        );
      }).toList(),
    );
  }
}
