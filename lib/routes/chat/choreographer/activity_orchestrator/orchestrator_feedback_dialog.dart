import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_feedback_repo.dart';

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
}) => showDialog<void>(
  context: context,
  builder: (_) => _OrchestratorFeedbackDialog(
    roomId: roomId,
    basedOnEventId: basedOnEventId,
  ),
);

class _OrchestratorFeedbackDialog extends StatefulWidget {
  final String roomId;
  final String basedOnEventId;

  const _OrchestratorFeedbackDialog({
    required this.roomId,
    required this.basedOnEventId,
  });

  @override
  State<_OrchestratorFeedbackDialog> createState() =>
      _OrchestratorFeedbackDialogState();
}

class _OrchestratorFeedbackDialogState
    extends State<_OrchestratorFeedbackDialog> {
  final TextEditingController _comment = TextEditingController();
  OrchestratorFeedbackPart _part = OrchestratorFeedbackPart.suggestion;
  bool _submitting = false;
  String? _error;

  bool get _canSubmit => _comment.text.trim().isNotEmpty && !_submitting;

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
                : (s) => setState(() => _part = s.first),
          ),
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
