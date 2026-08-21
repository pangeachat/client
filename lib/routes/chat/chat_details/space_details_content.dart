import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
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
import 'package:fluffychat/routes/world/panel_header.dart';
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
  /// headers and the pushed subpage's header title, so the two can't drift.
  String title(BuildContext context) => switch (this) {
    SpaceSettingsTabs.course => L10n.of(context).coursePlan,
    SpaceSettingsTabs.chat => L10n.of(context).chats,
    SpaceSettingsTabs.participants => L10n.of(context).participants,
    _ => L10n.of(context).more,
  };
}

/// The course card's render-state dispatcher. Each state is its own widget,
/// in precedence order: the compact peek (just the progress bar) wins over
/// everything, then a pushed section subpage ([_CourseSectionSubpage]), then
/// the full card ([_CourseCardBody]). Titles and the close control live in
/// [SpaceDetailsHeader], above this body.
class SpaceDetailsContent extends StatelessWidget {
  final SpaceDetailsController controller;
  final Room room;

  const SpaceDetailsContent(this.controller, this.room, {super.key});

  /// The card's horizontal content inset. Sections apply it individually —
  /// the page itself carries no horizontal padding — so the dividers between
  /// sections run edge-to-edge (#8357 design).
  static const EdgeInsets sectionPadding = EdgeInsets.symmetric(
    horizontal: 16.0,
  );

  /// Below this incoming BODY height (the card minus its header) the course
  /// card renders only the progress bar — the collapsed mobile peek (the nav
  /// cavity clips there). The wide/web panel and the expanded sheet are always
  /// well above it. The old whole-card threshold was 168 with the ~56px header
  /// row inside the body; the header now sits above the body, so the same
  /// cavity heights trigger at 112. See [build].
  static const double _kCompactCardMaxHeight = 112.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The collapsed mobile peek gives the card just enough height for the
        // header + progress bar and the nav cavity clips there. A section
        // subpage can't shrink into that short box (it overflows), so compact
        // outranks the subpage token; the sections slide in when the learner
        // drags the sheet up (#7597).
        final compact =
            constraints.maxHeight.isFinite &&
            constraints.maxHeight < _kCompactCardMaxHeight;
        if (compact) {
          // The nav cavity hands the peek TIGHT height constraints, which
          // would inflate the bar's fixed-height box to fill the slot; Align
          // restores loose constraints so the peek bar renders at the same
          // height as on the full page.
          return Padding(
            padding: sectionPadding,
            child: Align(
              alignment: Alignment.topCenter,
              child: CourseProgressBar(
                objectivesProvider: controller.objectivesProvider,
              ),
            ),
          );
        }

        final section = controller.expandedSection;
        if (section != null) {
          return _CourseSectionSubpage(controller, room, section);
        }
        return _CourseCardBody(controller, room);
      },
    );
  }
}

/// The course card's header — the shared [PanelHeader] chrome, so the card's
/// spacing and left-aligned title can't drift from the other workspace panels
/// (the chat list, settings). The panel's close control rides at the leading
/// edge — X/← for the card, and, because `<section>/all` reads as pushed from
/// the token, a pop-one-level ← titled with the section on its subpage (the
/// close-affordance rule, routing.instructions.md).
class SpaceDetailsHeader extends StatelessWidget {
  final SpaceDetailsController controller;
  final Room room;

  const SpaceDetailsHeader(this.controller, this.room, {super.key});

  @override
  Widget build(BuildContext context) {
    final leading =
        controller.widget.embeddedCloseButton ?? const SizedBox.shrink();
    final section = controller.expandedSection;
    if (section != null) {
      // Breadcrumb: only the course title truncates, so the subpage's own
      // name is always fully visible.
      return PanelHeader(
        leading: leading,
        title: section.title(context),
        titleWidget: Row(
          children: [
            Flexible(
              child: Text(
                room.getLocalizedDisplayname(MatrixLocals(L10n.of(context))),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Text(' > '),
            Text(section.title(context)),
          ],
        ),
      );
    }
    return PanelHeader(
      leading: leading,
      title: room.getLocalizedDisplayname(MatrixLocals(L10n.of(context))),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
    );
  }
}

/// The full course card: the single scrollable sections page.
class _CourseCardBody extends StatelessWidget {
  final SpaceDetailsController controller;
  final Room room;

  const _CourseCardBody(this.controller, this.room);

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
        title: l10n.starsToUnlockObjectiveTitle,
        description: l10n.starsToUnlockObjectiveDesc,
        icon: const Icon(Icons.star_outline, size: 30.0),
        onPressed: controller.setStarsToUnlockObjective,
        enabled: room.isRoomAdmin,
        trailing: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            "${room.teacherMode.starsToUnlockObjective ?? kDefaultStarsToUnlockObjective}",
            style: Theme.of(context).textTheme.bodyMedium,
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: FluffyThemes.isColumnMode(context) ? 12.0 : 4.0,
      ),
      child: CourseOverview(
        controller: controller,
        room: room,
        moreButtons: _moreButtons(context),
        onInvite: controller.openInvite,
        initialSection: controller.widget.activeTab,
      ),
    );
  }
}

/// A section's full subpage, pushed within the card (`<section>/all` in the
/// course token): the full course plan, the complete chat list, or the member
/// cards. Its back control and section title are the card's header
/// ([SpaceDetailsHeader]) — this body renders no navigation of its own.
class _CourseSectionSubpage extends StatelessWidget {
  final SpaceDetailsController controller;
  final Room room;
  final SpaceSettingsTabs section;

  const _CourseSectionSubpage(this.controller, this.room, this.section);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: SpaceDetailsContent.sectionPadding,
      child: switch (section) {
        SpaceSettingsTabs.course => Column(
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
        ),
        SpaceSettingsTabs.chat => CourseChats(
          room.id,
          activeChat: null,
          client: room.client,
        ),
        _ => SingleChildScrollView(
          child: Column(
            children: [
              const InstructionsInlineTooltip(
                instructionsEnum: InstructionsEnum.courseParticipantTooltip,
                padding: EdgeInsets.only(bottom: 16.0, left: 16.0, right: 16.0),
              ),
              RoomParticipantsSection(room: room),
            ],
          ),
        ),
      },
    );
  }
}
