import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_chat_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_participant_indicator.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_summary_unsubscribed_card.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_status_widget.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ActivityUserSummaries extends StatelessWidget {
  final ChatController controller;

  const ActivityUserSummaries({super.key, required this.controller});

  @override
  Widget build(BuildContext context) =>
      ActivitySummaryCards(activityController: controller.activityController);
}

/// The activity's summary in the chat: one card per learner who has finished.
/// A learner sees their own card as soon as they finish, and the others' join
/// as each of them finishes (org doc activity-summary.instructions.md, "The
/// experience").
class ActivitySummaryCards extends StatelessWidget {
  final ActivityChatController activityController;

  const ActivitySummaryCards({super.key, required this.activityController});

  Room get room => activityController.room;

  /// How many picker circles the subscription gate draws: one per learner who
  /// actually took a role, falling back to the plan's designed role count
  /// while the room holds no assignments yet. Both are room state the gate can
  /// read without the summary it will never receive (#8860).
  int get _skeletonRoleCount {
    final assigned = room.assignedRoles?.length ?? 0;
    if (assigned > 0) return assigned;
    return room.activityPlan?.roles.length ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    // The subscription gate stands HERE, in the summary's own place, rather
    // than as a line in the finished-status bar — a gate that fills the space
    // the feature would have filled is the pattern every other one follows
    // (#8860). Checked before the summary state below, because an unsubscribed
    // learner never has a summary to read it from.
    if (!MatrixState
        .pangeaController
        .subscriptionController
        .showSubscriptionGatedContent) {
      return room.hasCompletedRole || room.isActivityFinished
          ? ActivitySummaryUnsubscribedCard(roleCount: _skeletonRoleCount)
          : const SizedBox.shrink();
    }

    return ValueListenableBuilder(
      valueListenable: activityController.summaryView,
      builder: (context, view, _) {
        if (view.cards.isEmpty) return const SizedBox();
        return ValueListenableBuilder(
          valueListenable: activityController.highlightedRole,
          builder: (context, highlightedRole, _) {
            final selected = view.cardFor(
              selectedParticipantId(
                participantIds: [for (final card in view.cards) card.userId],
                highlightedUserId: highlightedRole?.userId,
                ownUserId: room.client.userID,
              ),
            )!;
            return _SummaryBlock(
              view: view,
              selected: selected,
              activityController: activityController,
            );
          },
        );
      },
    );
  }
}

/// The summary's box: the session as a whole above the rule, the picked
/// learner's card below it.
class _SummaryBlock extends StatelessWidget {
  final ActivitySummaryView view;
  final ActivitySummaryCardView selected;
  final ActivityChatController activityController;

  const _SummaryBlock({
    required this.view,
    required this.selected,
    required this.activityController,
  });

  @override
  Widget build(BuildContext context) {
    final room = activityController.room;
    final groupSummary = view.groupSummary;
    final header = [
      // Only the whole room finishing is "all finished"; until then the
      // finished-status bar says the learner is waiting for the rest.
      if (room.isActivityFinished)
        Text(L10n.of(context).activityFinishedMessage),
      if (groupSummary != null) Text(groupSummary, textAlign: TextAlign.center),
    ];

    return Center(
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            margin: const EdgeInsets.all(16.0),
            // The block keeps the width the goal header and plan page use, so
            // a long feedback grows downward instead of running edge to edge.
            constraints: const BoxConstraints(
              maxWidth: FluffyThemes.columnWidth * 1.5,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withAlpha(128),
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Column(
              spacing: 12.0,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (header.isNotEmpty) ...[
                  Center(
                    child: Column(
                      spacing: 6.0,
                      mainAxisSize: MainAxisSize.min,
                      children: header,
                    ),
                  ),
                  // Everything below the rule is about the picked learner —
                  // their stars and their card, swapping together. Above it is
                  // the session as a whole, which no pick changes (#8678).
                  const Divider(height: 1),
                ],
                ActivityParticipantSummaries(
                  view: view,
                  selected: selected,
                  activityController: activityController,
                ),
              ],
            ),
          ),
          // Feedback asks the bot to remake the picked card, so it shows only
          // while the bot is still in the room to answer.
          if (selected.canRequest && selected.participant != null)
            Positioned(
              right: 18.0,
              top: 18.0,
              child: IconButton(
                tooltip: L10n.of(context).feedbackButton,
                icon: const Icon(Icons.flag_outlined),
                onPressed: () => activityController.submitSummaryFeedback(
                  context,
                  userId: selected.userId,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Placeholder shown where a card will land while it is being generated.
class _SummaryLoading extends StatelessWidget {
  const _SummaryLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 12.0,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          L10n.of(context).generatingSummary,
          style: const TextStyle(fontStyle: FontStyle.italic),
          textAlign: TextAlign.center,
        ),
        const SizedBox(
          height: 36.0,
          width: 36.0,
          child: CircularProgressIndicator(),
        ),
      ],
    );
  }
}

/// A card failed. The retry asks the bot, so it shows only while the bot is
/// still in the room to answer.
class _SummaryError extends StatelessWidget {
  final VoidCallback? onRetry;

  const _SummaryError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 8,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.school_outlined, size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                L10n.of(context).activitySummaryError,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        if (onRetry != null)
          TextButton(
            onPressed: onRetry,
            child: Text(L10n.of(context).requestSummaries),
          ),
      ],
    );
  }
}

/// Whose card the summary shows: whoever the learner picked, else their own,
/// else the first so the summary is never empty (#8289).
String selectedParticipantId({
  required List<String> participantIds,
  required String? highlightedUserId,
  required String? ownUserId,
}) =>
    participantIds.firstWhereOrNull((id) => id == highlightedUserId) ??
    participantIds.firstWhereOrNull((id) => id == ownUserId) ??
    participantIds.first;

/// The plan role held by the participant whose card is up — the source of the
/// goal list under the picker. Null when the room holds no role for them, or
/// when the plan can no longer resolve that role (a pinned version evicted in
/// favor of one with regenerated role ids), in which case there are no goals
/// to show (#8672).
ActivityRole? selectedParticipantRole({
  required Map<String, ActivityRole>? planRoles,
  required Iterable<ActivityRoleModel> assignedRoles,
  required String participantId,
}) {
  final assigned = assignedRoles.firstWhereOrNull(
    (role) => role.userId == participantId,
  );
  if (assigned == null) return null;
  return planRoles?[assigned.id];
}

/// The cards under the rule: one learner's at a time — the viewer's own by
/// default — with a picker for everyone else. A single card is what keeps the
/// section free of horizontal scrolling (#8289).
class ActivityParticipantSummaries extends StatelessWidget {
  final ActivitySummaryView view;
  final ActivitySummaryCardView selected;
  final ActivityChatController activityController;

  const ActivityParticipantSummaries({
    super.key,
    required this.view,
    required this.selected,
    required this.activityController,
  });

  @override
  Widget build(BuildContext context) {
    final room = activityController.room;
    final selectedRole = selectedParticipantRole(
      planRoles: room.activityPlan?.roles,
      assignedRoles: room.assignedRoles?.values ?? const [],
      participantId: selected.userId,
    );
    final awarded = room.orchestratorAwardedGoals;
    final participant = selected.participant;

    return Column(
      spacing: 12.0,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (view.cards.length > 1)
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            alignment: WrapAlignment.center,
            children: [
              for (final card in view.cards)
                _ParticipantPickerTile(
                  userId: card.userId,
                  activityController: activityController,
                  selected: card.userId == selected.userId,
                ),
            ],
          ),
        // The goal header steps aside once the summary lands, so the stars
        // come along with it (#8289) — and they follow the picker, so a
        // learner reading somebody else's card sees that person's goals, not
        // their own (#8672).
        if (selectedRole != null && selectedRole.allGoals.isNotEmpty)
          Column(
            spacing: 8.0,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final goal in selectedRole.allGoals)
                GoalStatusWidget(
                  goal: goal,
                  complete: awarded.isGoalCompletedForRole(
                    selectedRole.id,
                    goal.id,
                    goalSlug: goal.goalSlug,
                  ),
                ),
            ],
          ),
        if (selected.isLoading)
          const _SummaryLoading()
        else if (participant != null) ...[
          if (selected.updateFailed)
            Text(
              L10n.of(context).activitySummaryUpdateFailed,
              style: const TextStyle(fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          _ParticipantSummaryCard(participant: participant, room: room),
        ] else
          _SummaryError(
            onRetry: selected.canRequest
                ? () =>
                      activityController.requestSummary(userId: selected.userId)
                : null,
          ),
      ],
    );
  }
}

/// One face in the picker row. Tapping it swaps the card below.
class _ParticipantPickerTile extends StatelessWidget {
  final String userId;
  final ActivityChatController activityController;
  final bool selected;

  const _ParticipantPickerTile({
    required this.userId,
    required this.activityController,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final room = activityController.room;
    final role = room.assignedRoles?.values.firstWhereOrNull(
      (role) => role.userId == userId,
    );
    if (role == null) return const SizedBox.shrink();

    // The assigned role id can be missing from the resolved plan when the
    // pinned plan version was evicted and a fallback version (with regenerated
    // role ids) was served — fall back to the role name in room state.
    final roleName =
        room.activityPlan?.roles[role.id]?.name ??
        role.role ??
        L10n.of(context).participant;

    return SizedBox(
      width: 100.0,
      child: ActivityParticipantIndicator(
        name: roleName,
        userId: userId,
        user: room.getParticipants().firstWhereOrNull((u) => u.id == userId),
        borderRadius: BorderRadius.circular(4),
        selected: selected,
        onTap: () => activityController.highlightRole(role),
        room: room,
      ),
    );
  }
}

/// One participant's feedback. The card grows to its text rather than
/// scrolling inside a fixed height (#8289).
class _ParticipantSummaryCard extends StatelessWidget {
  final ParticipantSummaryModel participant;
  final Room room;

  const _ParticipantSummaryCard({
    required this.participant,
    required this.room,
  });

  @override
  Widget build(BuildContext context) {
    final user = room.getParticipants().firstWhereOrNull(
      (u) => u.id == participant.participantId,
    );
    final role = room.assignedRoles?.values.firstWhereOrNull(
      (role) => role.userId == participant.participantId,
    );
    final displayName =
        user?.localizedDisplayname(L10n.of(context)) ??
        participant.participantId.localpart ??
        participant.participantId;
    // A "1st" ranks the learner against the room, which only means something
    // once everyone's use is in.
    final superlatives = room.isActivityFinished
        ? room.activitySummaryAnalytics?.generateSuperlatives()
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12.0),
      decoration: ShapeDecoration(
        color: Theme.of(context).pangea.goldFixedDim,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Column(
        spacing: 8.0,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            spacing: 10.0,
            mainAxisSize: MainAxisSize.min,
            children: [
              Avatar(
                name: participant.participantId.localpart,
                mxContent: user?.avatarUrl,
                size: 40,
              ),
              Flexible(
                child: Text(
                  "${role?.role ?? L10n.of(context).participant} | $displayName",
                  style: TextStyle(
                    fontSize: 14.0,
                    color: Theme.of(context).pangea.onGoldFixed,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Text(
            participant.displayFeedback(displayName),
            style: TextStyle(
              fontSize: 14.0,
              color: Theme.of(context).pangea.onGoldFixed,
            ),
          ),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  participant.cefrLevel,
                  style: TextStyle(
                    fontSize: 14.0,
                    color: Theme.of(context).pangea.onGoldFixed,
                  ),
                ),
                if (superlatives?['vocab']?.contains(
                      participant.participantId,
                    ) ==
                    true)
                  const SuperlativeTile(icon: Symbols.dictionary),
                if (superlatives?['grammar']?.contains(
                      participant.participantId,
                    ) ==
                    true)
                  const SuperlativeTile(icon: Symbols.toys_and_games),
                if (superlatives?['xp']?.contains(participant.participantId) ==
                    true)
                  const SuperlativeTile(icon: Icons.star),
                if (participant.superlatives.isNotEmpty)
                  Text(
                    participant.superlatives.first,
                    style: TextStyle(
                      fontSize: 14.0,
                      color: Theme.of(context).pangea.onGoldFixed,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SuperlativeTile extends StatelessWidget {
  final IconData icon;

  const SuperlativeTile({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    // Only ever drawn on the gold summary card.
    final ink = Theme.of(context).pangea.onGoldFixed;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: ink),
        const SizedBox(width: 2),
        Text("1st", style: TextStyle(fontSize: 14.0, color: ink)),
      ],
    );
  }
}
