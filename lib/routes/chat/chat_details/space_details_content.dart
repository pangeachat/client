import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics_access/course_settings_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/features/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/features/join_codes/share_room_button.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_overview.dart';
import 'package:fluffychat/routes/chat/chat_details/delete_space_dialog.dart';
import 'package:fluffychat/routes/chat/chat_details/room_details_buttons.dart';
import 'package:fluffychat/routes/chat/chat_details/room_participants_widget.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details.dart';
import 'package:fluffychat/routes/chat_list/course_chats_page.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_objectives_view.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_progress_bar.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

/// The course page's sections (the retired tab row's identities, kept as the
/// URL vocabulary): a section name in the course token scrolls the single page
/// to that section; `<section>/all` pushes its full subpage. `analytics` is
/// retired from the UI (#7709 — the admin dashboard owns course analytics) but
/// stays parseable so inbound links degrade to the page top.
enum SpaceSettingsTabs {
  chat,
  course,
  participants,
  analytics,
  more;

  static SpaceSettingsTabs? fromString(String value) {
    return SpaceSettingsTabs.values.firstWhereOrNull((e) => e.name == value);
  }

  /// The section's display title — shared by the course page's section
  /// headers and the pushed subpage's back row, so the two can't drift.
  String title(BuildContext context) => switch (this) {
    SpaceSettingsTabs.course => L10n.of(context).coursePlan,
    SpaceSettingsTabs.chat => L10n.of(context).chats,
    SpaceSettingsTabs.participants => L10n.of(context).participants,
    _ => L10n.of(context).more,
  };
}

class SpaceDetailsContent extends StatelessWidget {
  final SpaceDetailsController controller;
  final Room room;

  const SpaceDetailsContent(this.controller, this.room, {super.key});

  /// The More section's rows. Every setting shows inline; admin-only rows are
  /// disabled (not hidden) for non-admins — one layout for all roles (#8357).
  List<ButtonDetails> _moreButtons(BuildContext context) {
    final L10n l10n = L10n.of(context);
    return [
      ButtonDetails(
        title: l10n.editCourse,
        description: l10n.editCourseDesc,
        icon: const Icon(Icons.edit_outlined, size: 30.0),
        onPressed: () => controller.openCoursePage(RoomSubpageEnum.edit),
        enabled: room.isRoomAdmin,
      ),
      ButtonDetails(
        title: l10n.changeCourse,
        description: l10n.changeCourseDesc,
        icon: const Icon(Icons.assignment_outlined, size: 30.0),
        onPressed: () => controller.openCoursePage(RoomSubpageEnum.addcourse),
        enabled: room.isRoomAdmin,
      ),
      ButtonDetails(
        title: l10n.teacherModeTitle,
        description: l10n.teacherModeDesc,
        icon: const Icon(Icons.school_outlined, size: 30.0),
        onPressed: () => showFutureLoadingDialog(
          context: context,
          future: () => room.setTeacherMode(
            room.teacherMode.copyWith(enabled: !room.isTeacherMode),
          ),
        ),
        enabled: room.isRoomAdmin,
        isToggle: true,
        value: room.isTeacherMode,
      ),
      ButtonDetails(
        title: l10n.starsToUnlockObjectiveTitle,
        description: l10n.starsToUnlockObjectiveDesc,
        icon: const Icon(Icons.star_outline, size: 30.0),
        onPressed: controller.setStarsToUnlockObjective,
        enabled: room.isRoomAdmin,
        trailing: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            "${room.teacherMode.starsToUnlockObjective ?? kDefaultStarsToUnlockObjective}",
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ),
      ButtonDetails(
        title: l10n.requireAnalyticsAccessTitle,
        description: l10n.requireAnalyticsAccessDesc,
        icon: const Icon(Symbols.bar_chart_4_bars, size: 30.0),
        onPressed: () => showFutureLoadingDialog(
          context: context,
          future: () => room.toggleRequireAnalyticsAccess(),
        ),
        enabled: room.isRoomAdmin,
        isToggle: true,
        value: room.requireAnalyticsAccess,
      ),
      ButtonDetails(
        title: l10n.permissions,
        description: l10n.permissionsDesc,
        icon: const Icon(Icons.edit_attributes_outlined, size: 30.0),
        onPressed: () => controller.openCoursePage(RoomSubpageEnum.permissions),
        enabled: room.isRoomAdmin,
      ),
      ButtonDetails(
        title: l10n.access,
        description: l10n.accessDesc,
        icon: const Icon(Icons.shield_outlined, size: 30.0),
        onPressed: () => controller.openCoursePage(RoomSubpageEnum.access),
        enabled: room.isRoomAdmin && room.spaceParents.isEmpty,
      ),
      ButtonDetails(
        title: l10n.createGroupChat,
        description: l10n.createGroupChatDesc,
        icon: const Icon(Symbols.chat_add_on, size: 30.0),
        onPressed: controller.addGroupChat,
        enabled:
            room.isRoomAdmin && room.canChangeStateEvent(EventTypes.SpaceChild),
      ),
      ButtonDetails(
        title: l10n.leave,
        description: l10n.leaveDesc,
        icon: const Icon(Icons.logout_outlined, size: 30.0),
        onPressed: controller.leaveCourse,
        enabled: room.membership == Membership.join,
      ),
      ButtonDetails(
        title: l10n.delete,
        description: l10n.deleteDesc,
        icon: const Icon(Icons.delete_outline, size: 30.0),
        onPressed: () => DeleteSpaceDialog.show(room, context),
        enabled: room.isRoomAdmin,
      ),
    ];
  }

  /// Below this incoming height the course card renders only its header and
  /// progress bar — the collapsed mobile peek (the nav cavity clips there). The
  /// wide/web panel and the expanded sheet are always well above it. See
  /// [build].
  static const double _kCompactCardMaxHeight = 168.0;

  @override
  Widget build(BuildContext context) {
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final displayname = room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    final expandedSection = controller.expandedSection;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The collapsed mobile peek gives the card just enough height for the
        // header + progress bar and the nav cavity clips there. The section
        // page can't shrink into that short box (it overflows), so below the
        // threshold we render ONLY the header + bar; the sections slide in
        // when the learner drags the sheet up (#7597).
        final compact =
            constraints.maxHeight.isFinite &&
            constraints.maxHeight < _kCompactCardMaxHeight;
        if (!compact && expandedSection != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A pushed subpage swaps the card header for a back row — the
              // back arrow pops to the course page at the section it came from
              // (the close-affordance rule, routing.instructions.md).
              Row(
                children: [
                  IconButton(
                    tooltip: L10n.of(context).back,
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.go(
                      WorkspaceNav.openCourseTab(
                        GoRouterState.of(context).uri,
                        tab: expandedSection,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      expandedSection.title(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8.0),
              Expanded(
                child: _ExpandedSectionBody(controller, room, expandedSection),
              ),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // world_v2: a space has no AppBar ([SpaceDetails] renders none),
            // so the left-panel close control — an X on desktop, a
            // back arrow on mobile — rides at the leading edge of the card
            // header. Dropping it would leave the course card with no way to
            // close. See routing.instructions.md.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (controller.widget.embeddedCloseButton != null)
                  controller.widget.embeddedCloseButton!,
                Expanded(
                  child: Text(
                    displayname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Normalized with the activity start page: share on the left,
                // focus on the right, and the shared `my_location` focus icon.
                if (room.joinCode != null)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ShareRoomButton(
                      room: room,
                      tooltip: L10n.of(context).shareCourse,
                      child: const Icon(Icons.share_outlined),
                    ),
                  ),
                // The one camera path that zooms (#7616): course selection
                // only pans, so this button zoom+pan-fits the map to all of
                // the course's activities.
                ValueListenableBuilder(
                  valueListenable: controller.objectivesProvider.questLoader,
                  builder: (context, _, _) {
                    if (controller
                        .objectivesProvider
                        .filteredObjectiveGroups
                        .isNotEmpty) {
                      return IconButton(
                        tooltip: L10n.of(context).focusOnMap,
                        icon: const Icon(Icons.my_location),
                        onPressed: MapCameraFocusRequests.request,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12.0),
            if (compact)
              // The collapsed peek keeps the progress bar under the header;
              // on the full page it lives in the Course-plan section (#8357).
              CourseProgressBar(
                objectivesProvider: controller.objectivesProvider,
              )
            else
              Expanded(
                child: CourseOverview(
                  controller: controller,
                  room: room,
                  moreButtons: _moreButtons(context),
                  onInvite: controller.openInvite,
                  initialSection: controller.widget.activeTab,
                ),
              ),
            if (!compact) SizedBox(height: isColumnMode ? 12.0 : 4.0),
          ],
        );
      },
    );
  }
}

/// The body of a section's full subpage, pushed within the card
/// (`<section>/all` in the course token): the full course plan, the complete
/// chat list, or the member cards.
class _ExpandedSectionBody extends StatelessWidget {
  final SpaceDetailsController controller;
  final Room room;
  final SpaceSettingsTabs section;

  const _ExpandedSectionBody(this.controller, this.room, this.section);

  @override
  Widget build(BuildContext context) {
    switch (section) {
      case SpaceSettingsTabs.course:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Pinned above the plan so course totals stay visible while
            // scrolling the Missions.
            CourseProgressBar(
              objectivesProvider: controller.objectivesProvider,
            ),
            const SizedBox(height: 8.0),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  controller.objectivesProvider.questLoader,
                  controller.objectivesProvider.progression,
                ]),
                builder: (context, _) => CourseObjectivesList(
                  room: room,
                  collapsibleMissions: true,
                  hasCompletedActivity: (activityId) => controller
                      .roomSummariesModel
                      .hasCompletedActivity(room.client.userID!, activityId),
                  objectivesProvider: controller.objectivesProvider,
                ),
              ),
            ),
          ],
        );
      case SpaceSettingsTabs.chat:
        return CourseChats(room.id, activeChat: null, client: room.client);
      default:
        return SingleChildScrollView(
          child: Column(
            children: [
              const InstructionsInlineTooltip(
                instructionsEnum: InstructionsEnum.courseParticipantTooltip,
                padding: EdgeInsets.only(bottom: 16.0, left: 16.0, right: 16.0),
              ),
              RoomParticipantsSection(room: room),
            ],
          ),
        );
    }
  }
}
