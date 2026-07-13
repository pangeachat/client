import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics_access/course_settings_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/features/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/features/join_codes/share_room_button.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/chat_details.dart';
import 'package:fluffychat/routes/chat/chat_details/delete_space_dialog.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/routes/chat/chat_details/room_details_buttons.dart';
import 'package:fluffychat/routes/chat/chat_details/room_participants_widget.dart';
import 'package:fluffychat/routes/chat/chat_details/space_analytics/space_analytics.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details_button_row.dart';
import 'package:fluffychat/routes/chat_list/course_chats_page.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_objectives_view.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_progress_bar.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

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

  SpaceSettingsTabs tab(BuildContext context) {
    final defaultTab = FluffyThemes.isColumnMode(context)
        ? SpaceSettingsTabs.course
        : SpaceSettingsTabs.chat;

    final activeTab = controller.widget.activeTab;
    if (activeTab != null) {
      return activeTab;
    }

    return defaultTab;
  }

  void setSelectedTab(SpaceSettingsTabs tab, BuildContext context) {
    // Switching tabs re-opens the course token with the new tab in its param —
    // a same-path query mutation that preserves any open right panel (e.g. the
    // analytics panel) by construction, instead of the old path nav that
    // dropped it. The course panel decodes the tab back out. See
    // routing.instructions.md.
    context.go(
      WorkspaceNav.openCourseTab(GoRouterState.of(context).uri, tab: tab),
    );
  }

  /// Open a course-management page (edit / access / permissions / change-course)
  /// as the card's DETAIL — a `coursepage` panel beside the card that coexists
  /// when width allows and folds to a push when not, keeping the `?m=` filter
  /// and the rest of the workspace. See `routing.instructions.md`.
  void _openCoursePage(BuildContext context, RoomSubpageEnum page) => context
      .go(WorkspaceNav.openCoursePage(GoRouterState.of(context).uri, page));

  List<ButtonDetails> _buttons(BuildContext context) {
    final L10n l10n = L10n.of(context);
    return [
      ButtonDetails(
        title: l10n.chats,
        icon: const Icon(Icons.chat_bubble_outline, size: 30.0),
        onPressed: () => setSelectedTab(SpaceSettingsTabs.chat, context),
        // world_v2: the course card lives in the left column, so the Chats
        // tab belongs in the card in both column and narrow mode.
        tab: SpaceSettingsTabs.chat,
      ),
      ButtonDetails(
        title: l10n.coursePlan,
        icon: const Icon(Icons.map_outlined, size: 30.0),
        onPressed: () => setSelectedTab(SpaceSettingsTabs.course, context),
        tab: SpaceSettingsTabs.course,
      ),
      ButtonDetails(
        title: l10n.participants,
        icon: const Icon(Icons.group_outlined, size: 30.0),
        onPressed: () =>
            setSelectedTab(SpaceSettingsTabs.participants, context),
        tab: SpaceSettingsTabs.participants,
      ),
      ButtonDetails(
        title: l10n.stats,
        icon: const Icon(Symbols.bar_chart_4_bars, size: 30.0),
        onPressed: () => setSelectedTab(SpaceSettingsTabs.analytics, context),
        enabled: room.isRoomAdmin,
        tab: SpaceSettingsTabs.analytics,
        // world_v2: the card has 4 primary tabs (chats / course plan /
        // participants / more); course stats live inside More for admins.
        showInMainView: false,
      ),
      ButtonDetails(
        title: l10n.invite,
        description: l10n.inviteDesc,
        icon: const Icon(Icons.person_add_outlined, size: 30.0),
        onPressed: () {
          InvitationFilter filter = InvitationFilter.knocking;
          if (room.getParticipants([Membership.knock]).isEmpty) {
            filter = room.pangeaSpaceParents.isNotEmpty
                ? InvitationFilter.space
                : InvitationFilter.contacts;
          }
          // world_v2: opens beside the card as a `coursepage` detail, with the
          // initial contact filter riding in the token param.
          context.go(
            WorkspaceNav.openCoursePage(
              GoRouterState.of(context).uri,
              RoomSubpageEnum.invite,
              filter: filter,
            ),
          );
        },
        enabled: room.canInvite,
        showInMainView: false,
      ),
      ButtonDetails(
        title: l10n.editCourse,
        description: l10n.editCourseDesc,
        icon: const Icon(Icons.edit_outlined, size: 30.0),
        onPressed: () => _openCoursePage(context, RoomSubpageEnum.edit),
        enabled: room.isRoomAdmin,
        showInMainView: false,
      ),
      ButtonDetails(
        title: L10n.of(context).changeCourse,
        description: L10n.of(context).changeCourseDesc,
        icon: const Icon(Icons.assignment_outlined, size: 30.0),
        onPressed: () => _openCoursePage(context, RoomSubpageEnum.addcourse),
        enabled: room.isRoomAdmin,
        showInMainView: false,
      ),
      ButtonDetails(
        title: L10n.of(context).teacherModeTitle,
        description: L10n.of(context).teacherModeDesc,
        icon: const Icon(Icons.school_outlined, size: 30.0),
        onPressed: () => showFutureLoadingDialog(
          context: context,
          future: () => room.setTeacherMode(
            room.teacherMode.copyWith(enabled: !room.isTeacherMode),
          ),
        ),
        enabled: room.isRoomAdmin,
        showInMainView: false,
        isToggle: true,
        value: room.isTeacherMode,
      ),
      ButtonDetails(
        title: L10n.of(context).activitiesToUnlockTopicTitle,
        description: L10n.of(context).activitiesToUnlockTopicDesc,
        icon: const Icon(Icons.lock_open_outlined, size: 30.0),
        onPressed: () async {
          int minActivities = 0;
          if (room.coursePlan != null) {
            // world_v2: the cap is the fewest activities in any mission of the
            // v3 quest outline (replaces the v1 per-topic activity count).
            final resp = await showFutureLoadingDialog(
              context: context,
              future: () async {
                final outline = await QuestRepo.outline(room.coursePlan!.uuid);
                return outline.result?.groups
                    .map((g) => g.activities.length)
                    .min;
              },
              showError: (e) => false,
            );

            if (resp.result != null) {
              minActivities = resp.result!;
            }
          }
          final current = room.teacherMode.activitiesToUnlockTopic;
          final resp = await showTextInputDialog(
            context: context,
            title: L10n.of(context).activitiesToUnlockTopicTitle,
            keyboardType: TextInputType.number,
            maxLength: 2,
            maxLines: 1,
            validator: (input) {
              final value = int.tryParse(input);
              if (value == null || value < 0) {
                return L10n.of(context).enterNumber;
              }
              if (value > minActivities) {
                return L10n.of(
                  context,
                ).minActivitiesPerTopicWarning(value, minActivities);
              }
              return null;
            },
            initialText: current != null ? "$current" : null,
          );

          if (resp == null) return;
          await showFutureLoadingDialog(
            context: context,
            future: () => room.setTeacherMode(
              room.teacherMode.copyWith(
                activitiesToUnlockTopic: int.parse(resp),
              ),
            ),
          );
        },
        enabled: room.isRoomAdmin,
        showInMainView: false,
        trailing: room.teacherMode.activitiesToUnlockTopic != null
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  "${room.teacherMode.activitiesToUnlockTopic}",
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              )
            : null,
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
        showInMainView: false,
        isToggle: true,
        value: room.requireAnalyticsAccess,
      ),
      ButtonDetails(
        title: l10n.permissions,
        description: l10n.permissionsDesc,
        icon: const Icon(Icons.edit_attributes_outlined, size: 30.0),
        onPressed: () => _openCoursePage(context, RoomSubpageEnum.permissions),
        enabled: room.isRoomAdmin,
        showInMainView: false,
      ),
      ButtonDetails(
        title: l10n.access,
        description: l10n.accessDesc,
        icon: const Icon(Icons.shield_outlined, size: 30.0),
        onPressed: () => _openCoursePage(context, RoomSubpageEnum.access),
        enabled: room.isRoomAdmin && room.spaceParents.isEmpty,
        showInMainView: false,
      ),
      ButtonDetails(
        title: l10n.createGroupChat,
        description: l10n.createGroupChatDesc,
        icon: const Icon(Symbols.chat_add_on, size: 30.0),
        onPressed: controller.addGroupChat,
        enabled:
            room.isRoomAdmin && room.canChangeStateEvent(EventTypes.SpaceChild),
        showInMainView: false,
      ),
      ButtonDetails(
        title: l10n.leave,
        description: l10n.leaveDesc,
        icon: const Icon(Icons.logout_outlined, size: 30.0),
        onPressed: () async {
          final confirmed = await showOkCancelAlertDialog(
            context: context,
            title: L10n.of(context).areYouSure,
            okLabel: L10n.of(context).leave,
            cancelLabel: L10n.of(context).no,
            message: L10n.of(context).leaveSpaceDescription,
            isDestructive: true,
          );
          if (confirmed != OkCancelResult.ok) return;
          final resp = await showFutureLoadingDialog(
            context: context,
            future: room.leaveSpace,
          );
          if (!resp.isError) {
            context.go(PRoutes.chatsList);
          }
        },
        enabled: room.membership == Membership.join,
        showInMainView: false,
      ),
      ButtonDetails(
        title: l10n.delete,
        description: l10n.deleteDesc,
        icon: const Icon(Icons.delete_outline, size: 30.0),
        onPressed: () => DeleteSpaceDialog.show(room, context),
        enabled: room.isRoomAdmin,
        showInMainView: false,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // The collapsed mobile peek gives the card just enough height for the
        // header + progress bar and the nav cavity clips there. The Expanded
        // tab body can't shrink into that short box (it overflows), so below
        // the threshold we render ONLY the header + bar; the tabs and content
        // slide in when the learner drags the sheet up (#7597, the Figma
        // mobile-default frame).
        final compact =
            constraints.maxHeight.isFinite &&
            constraints.maxHeight < _kCompactCardMaxHeight;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // world_v2: a space has no AppBar (PangeaRoomDetailsView passes null
            // for spaces), so the left-panel close control — an X on desktop, a
            // back arrow on mobile — rides at the leading edge of the card
            // header. Dropping it would leave the course card with no way to
            // close. See routing.instructions.md.
            //
            // Shared header (web + mobile, #7597): [X · title · share]. The one
            // web/mobile difference is the tab labels below — RoomDetailsButton's
            // width-driven `mini`. No large course avatar (removed), and the
            // language/level/module chips moved to the top of the More tab.
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
                // The one camera path that zooms (#7616): course selection
                // only pans, so this button zoom+pan-fits the map to all of
                // the course's activities.
                if (controller
                    .objectivesProvider
                    .filteredObjectiveGroups
                    .isNotEmpty)
                  IconButton(
                    tooltip: L10n.of(context).focusOnMap,
                    icon: const Icon(Icons.filter_center_focus),
                    onPressed: MapCameraFocusRequests.request,
                  ),
                if (room.joinCode != null)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ShareRoomButton(
                      room: room,
                      tooltip: L10n.of(context).shareCourse,
                      child: const Icon(Icons.share_outlined),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12.0),
            // The overall course progress bar rides ABOVE the tabs so it shows on
            // every tab and survives the collapsed mobile peek (the objective list,
            // where it used to live, isn't mounted then). Only the course has a
            // bar; per-Mission rows show just their stars (#7597).
            CourseProgressBar(
              objectivesProvider: controller.objectivesProvider,
            ),
            if (!compact) ...[
              SizedBox(height: isColumnMode ? 24.0 : 12.0),
              SpaceDetailsButtonRow(
                controller: controller,
                room: room,
                selectedTab: tab(context),
                onTabSelected: (tab) => setSelectedTab(tab, context),
                buttons: _buttons(context),
              ),
              SizedBox(height: isColumnMode ? 30.0 : 14.0),
              Expanded(
                child: Builder(
                  builder: (context) {
                    switch (tab(context)) {
                      case SpaceSettingsTabs.chat:
                        return CourseChats(
                          room.id,
                          activeChat: null,
                          client: room.client,
                        );
                      case SpaceSettingsTabs.course:
                        // world_v2: the course plan is a sequence of learning
                        // objectives, each satisfied by interchangeable activities
                        // (no longer grouped by city).
                        return ListenableBuilder(
                          listenable: Listenable.merge([
                            controller.objectivesProvider.questLoader,
                            controller.objectivesProvider.progression,
                          ]),
                          builder: (context, _) => CourseObjectivesList(
                            room: room,
                            hasCompletedActivity: controller
                                .roomSummariesModel
                                .hasCompletedActivity,
                            objectivesProvider: controller.objectivesProvider,
                          ),
                        );
                      case SpaceSettingsTabs.participants:
                        return SingleChildScrollView(
                          child: Column(
                            children: [
                              const InstructionsInlineTooltip(
                                instructionsEnum:
                                    InstructionsEnum.courseParticipantTooltip,
                                padding: EdgeInsets.only(
                                  bottom: 16.0,
                                  left: 16.0,
                                  right: 16.0,
                                ),
                              ),
                              RoomParticipantsSection(room: room),
                            ],
                          ),
                        );
                      case SpaceSettingsTabs.analytics:
                        return SingleChildScrollView(
                          child: Center(child: SpaceAnalytics(roomId: room.id)),
                        );
                      case SpaceSettingsTabs.more:
                        final buttons = _buttons(
                          context,
                        ).where((b) => !b.showInMainView && b.visible).toList();

                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Course meta at the top of More: the description, then
                              // the language/level/module chips in a row beneath it
                              // (moved out of the header, #7597).
                              if (room.topic.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12.0),
                                  child: Text(
                                    room.topic,
                                    style: TextStyle(
                                      fontSize: isColumnMode ? 16.0 : 12.0,
                                    ),
                                  ),
                                ),
                              if (room.coursePlan != null)
                                Padding(
                                  padding: EdgeInsets.only(
                                    bottom: isColumnMode ? 30.0 : 14.0,
                                  ),
                                  child: CourseInfoChips(
                                    room.coursePlan!.uuid,
                                    fontSize: 12.0,
                                    iconSize: 12.0,
                                  ),
                                ),
                              Column(
                                spacing: 10.0,
                                mainAxisSize: MainAxisSize.min,
                                children: buttons.map((b) {
                                  return Opacity(
                                    opacity: b.enabled ? 1.0 : 0.5,
                                    child: b.isToggle
                                        ? SwitchListTile(
                                            title: Text(b.title),
                                            subtitle: b.description != null
                                                ? Text(b.description!)
                                                : null,
                                            secondary: b.icon,
                                            value: b.value,
                                            onChanged: b.enabled
                                                ? (value) {
                                                    b.onPressed?.call();
                                                  }
                                                : null,
                                            activeThumbColor:
                                                AppConfig.activeToggleColor,
                                          )
                                        : ListTile(
                                            title: Text(b.title),
                                            subtitle: b.description != null
                                                ? Text(b.description!)
                                                : null,
                                            leading: b.icon,
                                            onTap: b.enabled
                                                ? () => b.onPressed?.call()
                                                : null,
                                            trailing: b.trailing,
                                          ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        );
                    }
                  },
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
