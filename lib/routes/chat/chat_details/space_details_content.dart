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
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/chat_details.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_overview.dart';
import 'package:fluffychat/routes/chat/chat_details/delete_space_dialog.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/routes/chat/chat_details/room_details_buttons.dart';
import 'package:fluffychat/routes/chat/chat_details/room_participants_widget.dart';
import 'package:fluffychat/routes/chat_list/course_chats_page.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_objectives_view.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_progress_bar.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
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
}

class SpaceDetailsContent extends StatelessWidget {
  final ChatDetailsController controller;
  final Room room;

  const SpaceDetailsContent(this.controller, this.room, {super.key});

  /// The sections with a full "See all" subpage. `more` shows everything
  /// inline, so an expanded token for it degrades to the section scroll.
  static const Set<SpaceSettingsTabs> _expandableSections = {
    SpaceSettingsTabs.course,
    SpaceSettingsTabs.chat,
    SpaceSettingsTabs.participants,
  };

  SpaceSettingsTabs? get _expandedSection {
    final tab = controller.widget.activeTab;
    if (tab == null || !controller.widget.expandedSection) return null;
    return _expandableSections.contains(tab) ? tab : null;
  }

  /// Open the invite flow beside the card, seated on the most relevant contact
  /// filter (knocking users first). See `routing.instructions.md`.
  void _openInvite(BuildContext context) {
    InvitationFilter filter = InvitationFilter.knocking;
    if (room.getParticipants([Membership.knock]).isEmpty) {
      filter = room.pangeaSpaceParents.isNotEmpty
          ? InvitationFilter.space
          : InvitationFilter.contacts;
    }
    context.go(
      WorkspaceNav.openCoursePage(
        GoRouterState.of(context).uri,
        RoomSubpageEnum.invite,
        filter: filter,
      ),
    );
  }

  /// Open a course-management page (edit / access / permissions / change-course)
  /// as the card's DETAIL — a `coursepage` panel beside the card that coexists
  /// when width allows and folds to a push when not, keeping the `?m=` filter
  /// and the rest of the workspace. See `routing.instructions.md`.
  void _openCoursePage(BuildContext context, RoomSubpageEnum page) => context
      .go(WorkspaceNav.openCoursePage(GoRouterState.of(context).uri, page));

  /// The More section's rows. Every setting shows inline; admin-only rows are
  /// disabled (not hidden) for non-admins — one layout for all roles (#8357).
  List<ButtonDetails> _moreButtons(BuildContext context) {
    final L10n l10n = L10n.of(context);
    return [
      ButtonDetails(
        title: l10n.editCourse,
        description: l10n.editCourseDesc,
        icon: const Icon(Icons.edit_outlined, size: 30.0),
        onPressed: () => _openCoursePage(context, RoomSubpageEnum.edit),
        enabled: room.isRoomAdmin,
      ),
      ButtonDetails(
        title: l10n.changeCourse,
        description: l10n.changeCourseDesc,
        icon: const Icon(Icons.assignment_outlined, size: 30.0),
        onPressed: () => _openCoursePage(context, RoomSubpageEnum.addcourse),
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
        onPressed: () => _setStarsToUnlockObjective(context),
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
        onPressed: () => _openCoursePage(context, RoomSubpageEnum.permissions),
        enabled: room.isRoomAdmin,
      ),
      ButtonDetails(
        title: l10n.access,
        description: l10n.accessDesc,
        icon: const Icon(Icons.shield_outlined, size: 30.0),
        onPressed: () => _openCoursePage(context, RoomSubpageEnum.access),
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
        onPressed: () => _leaveCourse(context),
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

  Future<void> _setStarsToUnlockObjective(BuildContext context) async {
    // The cap is the lowest-content Mission's earnable stars — the sum
    // of one player's earnable stars (goals per role) across its
    // activities. A value above it could never be satisfied there; the
    // resolver also clamps at resolve time as content changes
    // (quests.instructions.md; #7663).
    int maxStars = 0;
    if (room.coursePlan != null) {
      final resp = await showFutureLoadingDialog(
        context: context,
        future: () async {
          final outline = await QuestRepo.outline(
            room.coursePlan!.uuid,
            // Course-admin read from inside the space: include the
            // owner's private activities so the star cap counts them.
            courseRoomId: room.id,
          );
          return outline.result?.groups
              .map(
                (g) => g.activities.fold(
                  0,
                  (sum, a) => sum + a.plan.earnableStars,
                ),
              )
              .min;
        },
        showError: (e) => false,
      );

      if (resp.result != null) {
        maxStars = resp.result!;
      }
    }
    final current =
        room.teacherMode.starsToUnlockObjective ??
        kDefaultStarsToUnlockObjective;
    if (!context.mounted) return;
    final resp = await showTextInputDialog(
      context: context,
      title: L10n.of(context).starsToUnlockObjectiveTitle,
      keyboardType: TextInputType.number,
      maxLength: 2,
      maxLines: 1,
      validator: (input) {
        final value = int.tryParse(input);
        if (value == null || value < 1) {
          return L10n.of(context).enterNumber;
        }
        if (maxStars > 0 && value > maxStars) {
          return L10n.of(context).maxStarsPerMissionWarning(maxStars);
        }
        return null;
      },
      initialText: "$current",
    );

    if (resp == null || !context.mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => room.setTeacherMode(
        room.teacherMode.copyWith(starsToUnlockObjective: int.parse(resp)),
      ),
    );
  }

  Future<void> _leaveCourse(BuildContext context) async {
    final confirmed = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).areYouSure,
      okLabel: L10n.of(context).leave,
      cancelLabel: L10n.of(context).no,
      message: L10n.of(context).leaveSpaceDescription,
      isDestructive: true,
    );
    if (confirmed != OkCancelResult.ok || !context.mounted) return;
    final resp = await showFutureLoadingDialog(
      context: context,
      future: room.leaveSpace,
    );
    if (!resp.isError && context.mounted) {
      // Leaving a course is the World/home reset: drop every panel and the
      // `?c=` scope, back to the world map at its personal default.
      context.go(WorkspaceNav.clearAll());
    }
  }

  String _sectionTitle(BuildContext context, SpaceSettingsTabs section) =>
      switch (section) {
        SpaceSettingsTabs.course => L10n.of(context).coursePlan,
        SpaceSettingsTabs.chat => L10n.of(context).chats,
        SpaceSettingsTabs.participants => L10n.of(context).participants,
        _ => L10n.of(context).more,
      };

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
    final expandedSection = _expandedSection;
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
                      _sectionTitle(context, expandedSection),
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
            // world_v2: a space has no AppBar (PangeaRoomDetailsView passes null
            // for spaces), so the left-panel close control — an X on desktop, a
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
                  onInvite: () => _openInvite(context),
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
  final ChatDetailsController controller;
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
