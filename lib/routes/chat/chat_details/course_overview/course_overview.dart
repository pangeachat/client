import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_catch_up.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_chats_preview.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_participants_preview.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_header.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_link.dart';
import 'package:fluffychat/routes/chat/chat_details/room_details_buttons.dart';
import 'package:fluffychat/routes/chat/chat_details/space_analytics/analytics_request_indicator.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details_content.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_objectives_view.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_progress_bar.dart';

/// The single scrollable course page (#8357, replacing the tab row): Course
/// plan / Chats / Participants / More as divider-separated sections, each with
/// its highlight inline and a link to its full subpage. Attention rows (knocks,
/// analytics-access requests) ride at the top and self-hide when empty. A
/// section in the course token's param scrolls the page to that section.
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
                      child: Text(room.topic),
                    ),
                  if (room.coursePlan != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: CourseInfoChips(
                        room.coursePlan!.uuid,
                        courseRoomId: room.id,
                        fontSize: 12.0,
                        iconSize: 12.0,
                      ),
                    ),
                  CourseCatchUp(room: room),
                  AnalyticsRequestIndicator(room: room),
                  Column(
                    key: _sectionKeys[SpaceSettingsTabs.course],
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CourseSectionHeader(
                        title: SpaceSettingsTabs.course.title(context),
                      ),
                      CourseProgressBar(
                        objectivesProvider:
                            widget.controller.objectivesProvider,
                      ),
                      const SizedBox(height: 8.0),
                      Text(
                        l10n.upNext.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      ListenableBuilder(
                        listenable: Listenable.merge([
                          widget.controller.objectivesProvider.questLoader,
                          widget.controller.objectivesProvider.progression,
                        ]),
                        builder: (context, _) => CourseObjectivesList(
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
                      ),
                      CourseSectionLink(
                        label: l10n.seeFullCoursePlan,
                        onTap: () => _openSubpage(SpaceSettingsTabs.course),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: SpaceDetailsContent.sectionPadding,
              child: Column(
                key: _sectionKeys[SpaceSettingsTabs.chat],
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CourseSectionHeader(
                    title: SpaceSettingsTabs.chat.title(context),
                  ),
                  CourseChatsPreview(room: room),
                  CourseSectionLink(
                    label: l10n.allChats,
                    onTap: () => _openSubpage(SpaceSettingsTabs.chat),
                  ),
                ],
              ),
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
                            label: Text(l10n.invite),
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
    return Column(
      spacing: 10.0,
      mainAxisSize: MainAxisSize.min,
      children: buttons.where((b) => b.visible).map((b) {
        return Opacity(
          opacity: b.enabled ? 1.0 : 0.5,
          child: b.isToggle
              ? SwitchListTile(
                  title: Text(b.title),
                  subtitle: b.description != null ? Text(b.description!) : null,
                  secondary: b.icon,
                  value: b.value,
                  onChanged: b.enabled ? (value) => b.onPressed?.call() : null,
                  activeThumbColor: AppConfig.activeToggleColor,
                )
              : ListTile(
                  title: Text(b.title),
                  subtitle: b.description != null ? Text(b.description!) : null,
                  leading: b.icon,
                  onTap: b.enabled ? () => b.onPressed?.call() : null,
                  trailing: b.trailing,
                ),
        );
      }).toList(),
    );
  }
}
