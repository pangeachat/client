import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_report_repo.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';

/// The prompt behind a goal star (staging only, for the team).
///
/// A filled star asks why it should not have been given; an empty one asks why
/// it should have been, and makes the reporter name the message they are
/// claiming as evidence. Either way the comment is required: it is the whole
/// diagnostic value of the report, and the server rejects a blank one.
///
/// Nothing about the star changes. The report is recorded against the turn and
/// the header is left exactly as it was.
Future<void> showGoalReportDialog({
  required BuildContext context,
  required Room room,
  required String roleId,
  required ActivityRoleGoal goal,
  required GoalReportDirection direction,
  Future<List<PangeaMessageEvent>> Function()? ownMessagesOverride,
}) => showDialog<void>(
  context: context,
  builder: (_) => _GoalReportDialog(
    room: room,
    roleId: roleId,
    goal: goal,
    direction: direction,
    // Captured HERE, from the context that opens the prompt, because the
    // prompt's own context resolves to the wrong messenger: the dialog route
    // lives on the root navigator, so `ScaffoldMessenger.of` inside it finds
    // the MaterialApp's messenger, which has no Scaffold registered to it —
    // every Scaffold belongs to the workspace shell's nested messenger
    // (`workspace_shell.dart`). A confirmation sent there asserts instead of
    // showing.
    messenger: ScaffoldMessenger.of(context),
    ownMessagesOverride: ownMessagesOverride,
  ),
);

class _GoalReportDialog extends StatefulWidget {
  final Room room;
  final String roleId;
  final ActivityRoleGoal goal;
  final GoalReportDirection direction;

  /// The messenger that shows the confirmation, resolved from the context that
  /// opened the prompt rather than from the prompt's own.
  final ScaffoldMessengerState messenger;

  /// Test seam: the reporter's own messages, without a Matrix client behind
  /// them. Null in the app, where they come from the room's timeline.
  final Future<List<PangeaMessageEvent>> Function()? ownMessagesOverride;

  const _GoalReportDialog({
    required this.room,
    required this.roleId,
    required this.goal,
    required this.direction,
    required this.messenger,
    this.ownMessagesOverride,
  });

  @override
  State<_GoalReportDialog> createState() => _GoalReportDialogState();
}

class _GoalReportDialogState extends State<_GoalReportDialog> {
  final TextEditingController _comment = TextEditingController();
  Event? _evidence;
  bool _submitting = false;
  String? _error;

  /// Null until the load finishes; empty when the reporter has sent nothing.
  List<_EvidenceOption>? _ownMessages;

  bool get _needsEvidence => widget.direction == GoalReportDirection.underAward;

  bool get _canSubmit =>
      _comment.text.trim().isNotEmpty &&
      !_submitting &&
      (!_needsEvidence || _evidence != null);

  @override
  void initState() {
    super.initState();
    if (_needsEvidence) _loadOwnMessages();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  /// A one-shot snapshot, not a live timeline: the messages a report can point
  /// at are already sent, so the list has nothing to follow.
  Future<void> _loadOwnMessages() async {
    final override = widget.ownMessagesOverride;
    final messages = override != null
        ? await override()
        : await _ownMessagesFromTimeline();
    if (!mounted) return;
    setState(() => _ownMessages = messages.map(_EvidenceOption.new).toList());
  }

  Future<List<PangeaMessageEvent>> _ownMessagesFromTimeline() async {
    final userId = widget.room.client.userID;
    final timeline = await widget.room.getTimeline();
    try {
      return timeline.events
          .where(
            (e) =>
                e.type == EventTypes.Message &&
                e.senderId == userId &&
                !e.redacted &&
                // An edit carries its own event id and would read as a second
                // copy of the message it replaces.
                e.relationshipType != RelationshipTypes.edit,
          )
          .map(
            (e) => PangeaMessageEvent(
              event: e,
              timeline: timeline,
              ownMessage: true,
            ),
          )
          .toList();
    } finally {
      timeline.cancelSubscriptions();
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await GoalReportRepo.submit(
      roomId: widget.room.id,
      roleId: widget.roleId,
      // Awards key on the content-derived slug; the id is the fallback for a
      // goal predating it. The server matches either.
      goalId: widget.goal.goalSlug ?? widget.goal.id,
      direction: widget.direction,
      comment: _comment.text,
      evidenceEventId: _evidence?.eventId,
      evidenceOriginTs: _evidence?.originServerTs.millisecondsSinceEpoch,
    );
    if (!mounted) return;

    if (result.isError) {
      // The repo already reported this; only decide what the reporter sees.
      // Every failure here is one they can act on — pick another star, name
      // another message, or try again — so none of them is swallowed.
      setState(() {
        _submitting = false;
        _error = _messageFor(result.asError!.error);
      });
      return;
    }

    final thanks = L10n.of(context).goalReportThanks;
    Navigator.of(context).pop();
    widget.messenger.showSnackBarAnnounced(SnackBar(content: Text(thanks)));
  }

  /// 404 and 503 get their own line because neither is something the reporter
  /// did wrong: one means the star predates the record needed to find its
  /// awarding turn, the other that the search gave up and a retry may work.
  /// 403 and 422 carry a server `detail` that names the specific mismatch —
  /// the wrong star, or the wrong message — which is more use to the team than
  /// any line written here.
  String _messageFor(Object error) {
    final l10n = L10n.of(context);
    final status = PangeaHttpException.statusCodeOf(error);
    if (status == 404) return l10n.goalReportErrorUnreportable;
    if (status == 503) return l10n.goalReportErrorRetry;
    final detail = error is PangeaHttpException ? error.detail : null;
    return detail ?? l10n.oopsSomethingWentWrong;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.goalReportTitle),
      // A fixed width, not the content's: AlertDialog sizes to its content's
      // intrinsic width, and a multiline TextField reports that as its text on
      // one line, so every typed character would widen the dialog.
      content: SizedBox(
        width: FluffyThemes.columnWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Which star this is about. The prompt alone does not say, and the
              // dialog covers the list the star was tapped in.
              Text(widget.goal.description, style: theme.textTheme.titleSmall),
              const SizedBox(height: 12.0),
              Text(
                _needsEvidence
                    ? l10n.goalReportUnderAwardPrompt
                    : l10n.goalReportOverAwardPrompt,
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _comment,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                maxLength: GoalReportRepo.maxCommentLength,
                enabled: !_submitting,
                decoration: InputDecoration(
                  hintText: l10n.orchestratorFeedbackCommentHint,
                  helperText: l10n.orchestratorFeedbackCommentRequired,
                  errorText: _error,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_needsEvidence) ...[
                const SizedBox(height: 8.0),
                Text(
                  l10n.goalReportPickMessage,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8.0),
                _EvidencePicker(
                  messages: _ownMessages,
                  selected: _evidence,
                  enabled: !_submitting,
                  onSelected: (e) => setState(() => _evidence = e),
                ),
              ],
            ],
          ),
        ),
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

/// One of the reporter's messages as the picker lists it.
class _EvidenceOption {
  /// The original event, never its latest edit: its id and timestamp are what
  /// the server resolves the nominated turn from.
  final Event event;

  /// What the reporter recognises the message by: the latest edit's text, or
  /// for a voice message the transcript already stored on it. Null for a voice
  /// message with no stored transcript — the picker reads only what is stored
  /// and never requests one, so opening a report cannot fan out a
  /// speech-to-text call per message.
  final String? text;

  _EvidenceOption(PangeaMessageEvent message)
    : event = message.event,
      text = message.isAudioMessage
          ? message.getSpeechToTextLocal()?.transcript.text.trim()
          : message.body;
}

/// The reporter's own messages, newest first, one of which is the evidence.
class _EvidencePicker extends StatelessWidget {
  /// Null while loading, empty when the reporter has sent nothing yet.
  final List<_EvidenceOption>? messages;
  final Event? selected;
  final bool enabled;
  final ValueChanged<Event> onSelected;

  const _EvidencePicker({
    required this.messages,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final messages = this.messages;
    if (messages == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: CircularProgressIndicator.adaptive(),
        ),
      );
    }
    if (messages.isEmpty) {
      return Text(
        L10n.of(context).goalReportNoMessages,
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    // A plain column, scrolled by the dialog's own view: a lazy ListView
    // cannot report an intrinsic height, and AlertDialog measures its content
    // with one.
    return RadioGroup<String>(
      groupValue: selected?.eventId,
      onChanged: (eventId) {
        final picked = messages.firstWhereOrNull(
          (m) => m.event.eventId == eventId,
        );
        if (picked != null) onSelected(picked.event);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final message in messages)
            RadioListTile<String>(
              value: message.event.eventId,
              enabled: enabled,
              dense: true,
              title: Text(
                message.text ?? L10n.of(context).voiceMessage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                message.event.originServerTs.localizedTime(context),
              ),
            ),
        ],
      ),
    );
  }
}
