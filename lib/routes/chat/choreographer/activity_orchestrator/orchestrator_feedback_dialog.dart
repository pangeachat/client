import 'package:flutter/material.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_feedback_repo.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_role_goal_completion.dart';

/// Internal reviewer feedback on an orchestrator turn (staging only).
///
/// The comment is required, not optional: the part selector says something is
/// wrong, never what is wrong, and the comment is the whole diagnostic value
/// of the flag. Submit stays disabled until one is typed, so a reviewer never
/// reaches the server's 422.
Future<void> showOrchestratorFeedbackDialog({
  required BuildContext context,
  required String roomId,
  required String basedOnEventId,
  required String ownRoleId,
  required List<OrchestratorRoleGoalCompletion> goalCompletion,
  ActivityPlanModel? activityPlan,
}) => showDialog<void>(
  context: context,
  builder: (_) => _OrchestratorFeedbackDialog(
    roomId: roomId,
    basedOnEventId: basedOnEventId,
    ownRoleId: ownRoleId,
    goalCompletion: goalCompletion,
    activityPlan: activityPlan,
  ),
);

/// One flaggable award: the role it belongs to and the exact `goal_id` string
/// the turn recorded. The id is sent back verbatim so the server can match it
/// against the stored turn; the description is only for display.
class _Award {
  final String roleId;
  final String goalId;
  final String description;
  const _Award(this.roleId, this.goalId, this.description);
}

class _OrchestratorFeedbackDialog extends StatefulWidget {
  final String roomId;
  final String basedOnEventId;
  final String ownRoleId;
  final List<OrchestratorRoleGoalCompletion> goalCompletion;
  final ActivityPlanModel? activityPlan;

  const _OrchestratorFeedbackDialog({
    required this.roomId,
    required this.basedOnEventId,
    required this.ownRoleId,
    required this.goalCompletion,
    this.activityPlan,
  });

  @override
  State<_OrchestratorFeedbackDialog> createState() =>
      _OrchestratorFeedbackDialogState();
}

class _OrchestratorFeedbackDialogState
    extends State<_OrchestratorFeedbackDialog> {
  final TextEditingController _comment = TextEditingController();
  OrchestratorFeedbackPart _part = OrchestratorFeedbackPart.suggestion;
  _Award? _award;
  bool _submitting = false;
  String? _error;

  late final List<_Award> _awards = _buildAwards();

  /// Flattens the turn's awards and resolves each id to its goal text where
  /// the activity plan has it. The id is what gets sent; the text only makes
  /// the choice legible.
  List<_Award> _buildAwards() {
    final out = <_Award>[];
    for (final entry in widget.goalCompletion) {
      final goals = widget.activityPlan?.roles[entry.roleId]?.allGoals ?? [];
      for (final id in entry.goalIds) {
        final match = goals.where((g) => g.goalSlug == id || g.id == id);
        out.add(_Award(entry.roleId, id, match.firstOrNull?.description ?? id));
      }
    }
    return out;
  }

  bool get _needsAward => _part == OrchestratorFeedbackPart.goalCompletion;

  bool get _canSubmit =>
      _comment.text.trim().isNotEmpty &&
      !_submitting &&
      (!_needsAward || _award != null);

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await OrchestratorFeedbackRepo.submit(
      roomId: widget.roomId,
      basedOnEventId: widget.basedOnEventId,
      part: _part,
      targetRoleId: _needsAward ? _award!.roleId : widget.ownRoleId,
      targetGoalId: _needsAward ? _award!.goalId : null,
      comment: _comment.text,
    );
    if (!mounted) return;

    if (result.isError) {
      // The repo already reported this; only decide what the reviewer sees.
      setState(() {
        _submitting = false;
        _error = L10n.of(context).oopsSomethingWentWrong;
      });
      return;
    }

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.of(context).orchestratorFeedbackThanks)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(l10n.orchestratorFeedbackTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<OrchestratorFeedbackPart>(
            segments: [
              ButtonSegment(
                value: OrchestratorFeedbackPart.suggestion,
                label: Text(l10n.orchestratorFeedbackPartSuggestion),
              ),
              ButtonSegment(
                value: OrchestratorFeedbackPart.goalCompletion,
                label: Text(l10n.orchestratorFeedbackPartGoals),
              ),
            ],
            selected: {_part},
            onSelectionChanged: _submitting
                ? null
                : (s) => setState(() {
                    _part = s.first;
                    _award = null;
                  }),
          ),
          if (_needsAward) ...[
            const SizedBox(height: 16.0),
            if (_awards.isEmpty)
              Text(
                l10n.orchestratorFeedbackNoAwards,
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              DropdownButtonFormField<_Award>(
                initialValue: _award,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.orchestratorFeedbackPickAward,
                  helperText: l10n.orchestratorFeedbackPickAwardRequired,
                ),
                items: _awards
                    .map(
                      (a) => DropdownMenuItem(
                        value: a,
                        child: Text(
                          '${a.roleId} — ${a.description}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _submitting
                    ? null
                    : (a) => setState(() => _award = a),
              ),
          ],
          const SizedBox(height: 16.0),
          TextField(
            controller: _comment,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            enabled: !_submitting,
            decoration: InputDecoration(
              hintText: l10n.orchestratorFeedbackCommentHint,
              helperText: l10n.orchestratorFeedbackCommentRequired,
              errorText: _error,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(l10n.orchestratorFeedbackSubmit),
        ),
      ],
    );
  }
}
