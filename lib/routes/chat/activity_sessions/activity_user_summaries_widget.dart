import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_participant_indicator.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_status_widget.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';

class ActivityUserSummaries extends StatelessWidget {
  final ChatController controller;

  const ActivityUserSummaries({super.key, required this.controller});

  Room get room => controller.room;

  @override
  Widget build(BuildContext context) {
    final summaryModel = room.visibleActivitySummaryByL1;
    if (summaryModel == null || summaryModel.hasError) {
      return const SizedBox();
    }

    final summary = summaryModel.summary;
    if (summary == null) {
      // Generation runs in the chat, in the same semi-transparent box the
      // summary will fill, so the finished-status bar doesn't grow and shove
      // the rating card around while we wait (#8018). A locally-recorded
      // failure overrides room state, which can't say "error" when the
      // network is down (#8362).
      return ValueListenableBuilder(
        valueListenable: controller.activityController.summaryFetchFailed,
        builder: (context, fetchFailed, _) =>
            summaryModel.isLoading && !fetchFailed
            ? const _SummaryLoading()
            : const SizedBox(),
      );
    }

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
                Center(
                  child: Column(
                    spacing: 6.0,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(L10n.of(context).activityFinishedMessage),
                      Text(summary.summary, textAlign: TextAlign.center),
                    ],
                  ),
                ),
                ActivityParticipantSummaries(
                  summary: summary,
                  controller: controller,
                  dividerAbove: goals.isNotEmpty,
                ),
              ],
            ),
          ),
          Positioned(
            right: 18.0,
            top: 18.0,
            child: IconButton(
              tooltip: L10n.of(context).feedbackButton,
              icon: const Icon(Icons.flag_outlined),
              onPressed: () =>
                  controller.activityController.submitSummaryFeedback(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder shown where the summary will land while it is being generated.
class _SummaryLoading extends StatelessWidget {
  const _SummaryLoading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        margin: const EdgeInsets.all(16.0),
        constraints: const BoxConstraints(maxWidth: 400.0),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withAlpha(128),
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Column(
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
        ),
      ),
    );
  }
}

/// Whose feedback the summary shows: whoever the learner picked, else their
/// own, else the first participant so the card is never empty (#8289).
ParticipantSummaryModel selectedParticipantSummary({
  required List<ParticipantSummaryModel> summaries,
  required String? highlightedUserId,
  required String? ownUserId,
}) =>
    summaries.firstWhereOrNull((p) => p.participantId == highlightedUserId) ??
    summaries.firstWhereOrNull((p) => p.participantId == ownUserId) ??
    summaries.first;

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

/// The feedback body of the summary: one participant's card at a time — the
/// viewer's own by default — with a picker for everyone else. A single card is
/// what keeps the section free of horizontal scrolling (#8289).
class ActivityParticipantSummaries extends StatelessWidget {
  final ActivitySummaryResponseModel summary;
  final ChatController controller;

  /// Rules the section off from the earned stars above it. The picker swaps
  /// only the card below the rule, and the stars are the learner's own either
  /// way — without the rule, switching participants reads as if it changed
  /// them (#8678).
  final bool dividerAbove;

  const ActivityParticipantSummaries({
    super.key,
    required this.summary,
    required this.controller,
    this.dividerAbove = false,
  });

  Room get room => controller.room;

  /// The summaries the room still holds a role for, in the plan's role order.
  List<ParticipantSummaryModel> get _roleSummaries {
    final assignedRoles = room.assignedRoles?.values ?? const [];
    return summary.participants
        .where(
          (p) => assignedRoles.any((role) => role.userId == p.participantId),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    // Reference plan may not be hydrated yet; the surface rebuilds once it
    // lands (ActivityPlanRepo).
    if (room.activityPlan == null) return const SizedBox.shrink();

    final roleSummaries = _roleSummaries;
    if (roleSummaries.isEmpty) return const SizedBox();

    return ValueListenableBuilder(
      valueListenable: controller.activityController.highlightedRole,
      builder: (context, highlightedRole, _) {
        final selected = selectedParticipantSummary(
          summaries: roleSummaries,
          highlightedUserId: highlightedRole?.userId,
          ownUserId: room.client.userID,
        );
        final selectedRole = selectedParticipantRole(
          planRoles: room.activityPlan?.roles,
          assignedRoles: room.assignedRoles?.values ?? const [],
          participantId: selected.participantId,
        );
        final awarded = room.orchestratorAwardedGoals;
        return Column(
          spacing: 12.0,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dividerAbove) const Divider(height: 1),
            if (roleSummaries.length > 1)
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                alignment: WrapAlignment.center,
                children: [
                  for (final participant in roleSummaries)
                    _ParticipantPickerTile(
                      participant: participant,
                      controller: controller,
                      selected:
                          participant.participantId == selected.participantId,
                    ),
                ],
              ),
            // The goal header steps aside once the summary lands, so the
            // stars come along with it (#8289) — and they follow the picker,
            // so a learner reading somebody else's card sees that person's
            // goals, not their own (#8672).
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
            _ParticipantSummaryCard(
              participant: selected,
              controller: controller,
            ),
          ],
        );
      },
    );
  }
}

/// One face in the picker row. Tapping it swaps the card below.
class _ParticipantPickerTile extends StatelessWidget {
  final ParticipantSummaryModel participant;
  final ChatController controller;
  final bool selected;

  const _ParticipantPickerTile({
    required this.participant,
    required this.controller,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    final role = room.assignedRoles?.values.firstWhereOrNull(
      (role) => role.userId == participant.participantId,
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
        userId: participant.participantId,
        user: room.getParticipants().firstWhereOrNull(
          (u) => u.id == participant.participantId,
        ),
        borderRadius: BorderRadius.circular(4),
        selected: selected,
        onTap: () => controller.activityController.highlightRole(role),
        room: room,
      ),
    );
  }
}

/// One participant's feedback. The card grows to its text rather than
/// scrolling inside a fixed height (#8289).
class _ParticipantSummaryCard extends StatelessWidget {
  final ParticipantSummaryModel participant;
  final ChatController controller;

  const _ParticipantSummaryCard({
    required this.participant,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
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
    final superlatives = room.activitySummaryByL1?.analytics
        ?.generateSuperlatives();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12.0),
      decoration: ShapeDecoration(
        color: Color.alphaBlend(
          Theme.of(context).colorScheme.surface.withAlpha(70),
          AppConfig.gold,
        ),
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
                  style: const TextStyle(fontSize: 14.0),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Text(
            participant.displayFeedback(displayName),
            style: const TextStyle(fontSize: 14.0),
          ),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  participant.cefrLevel,
                  style: const TextStyle(fontSize: 14.0),
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
                    style: const TextStyle(fontSize: 14.0),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurface),
        const SizedBox(width: 2),
        const Text("1st", style: TextStyle(fontSize: 14.0)),
      ],
    );
  }
}
