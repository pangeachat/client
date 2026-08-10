import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_dialog.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/practice_controller.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/practice_record_controller.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_choice.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

/// Whether a word→content pair in a practice exercise can be flagged for
/// content feedback, and if not, why.
enum PracticePairEligibility {
  /// Content came from the lemma dictionary and can be reported.
  flaggable,

  /// The emoji was set by the user themselves — there is nothing to report
  /// to the server; it can be changed from the word card instead.
  userSetEmoji,

  /// The pair was already matched correctly. Regenerating it would strand
  /// the recorded answer and allow re-earning XP on the new content.
  alreadyMatched,
}

/// Eligibility rule for a single pair, kept pure so it can be unit-tested
/// without Matrix state.
PracticePairEligibility practicePairEligibility({
  required bool isEmojiExercise,
  required String choiceContent,
  required String? userSetEmoji,
  required bool alreadyMatchedCorrectly,
}) {
  if (isEmojiExercise &&
      userSetEmoji != null &&
      choiceContent == userSetEmoji) {
    return PracticePairEligibility.userSetEmoji;
  }
  if (alreadyMatchedCorrectly) {
    return PracticePairEligibility.alreadyMatched;
  }
  return PracticePairEligibility.flaggable;
}

typedef PracticeFeedbackOutcome = ({
  LemmaInfoResponse prior,
  LemmaInfoResponse updated,
});

/// Flag dialog for emoji / meaning practice exercises. The user picks the
/// word→content pair that looks wrong and describes the problem; the flagged
/// lemma's dictionary row is regenerated with that feedback. Pops with a
/// [PracticeFeedbackOutcome] on success, null on cancel.
class PracticeExerciseFeedbackDialog extends StatefulWidget {
  final MatchPracticeExerciseModel activity;
  final PracticeTarget target;
  final PracticeController controller;

  const PracticeExerciseFeedbackDialog({
    super.key,
    required this.activity,
    required this.target,
    required this.controller,
  });

  @override
  State<PracticeExerciseFeedbackDialog> createState() =>
      PracticeExerciseFeedbackDialogState();
}

class PracticeExerciseFeedbackDialogState
    extends State<PracticeExerciseFeedbackDialog> {
  PracticeExerciseChoice? _selected;

  bool get _isEmojiExercise => widget.activity is EmojiPracticeExerciseModel;

  @override
  void initState() {
    super.initState();
    _selected = widget.activity.matchContent.choices.firstWhereOrNull(
      (choice) => _eligibility(choice) == PracticePairEligibility.flaggable,
    );
  }

  PangeaToken? _tokenForChoice(PracticeExerciseChoice choice) => widget
      .activity
      .tokens
      .firstWhereOrNull((t) => t.vocabConstructID == choice.form.cId);

  PracticePairEligibility _eligibility(PracticeExerciseChoice choice) {
    final token = _tokenForChoice(choice);
    return practicePairEligibility(
      isEmojiExercise: _isEmojiExercise,
      choiceContent: choice.choiceContent,
      userSetEmoji: token?.vocabConstructID.userSetEmoji,
      alreadyMatchedCorrectly:
          token != null &&
          PracticeRecordController.isCompleteByToken(widget.target, token),
    );
  }

  /// The content as displayed, used as feedback context if the lemma cache
  /// has expired by the time the user submits.
  LemmaInfoResponse _priorContent(PracticeExerciseChoice choice) =>
      _isEmojiExercise
      ? LemmaInfoResponse(emoji: [choice.choiceContent], meaning: '')
      : LemmaInfoResponse(emoji: const [], meaning: choice.choiceContent);

  Future<void> _submit(String feedbackText) async {
    final selected = _selected;
    if (selected == null) return;

    final resp = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final result = await widget.controller.submitLemmaFeedback(
          cId: selected.form.cId,
          priorContent: _priorContent(selected),
          feedbackText: feedbackText,
          flaggedChoice: selected.choiceContent,
          target: widget.target,
        );
        if (result.isError) {
          Error.throwWithStackTrace(
            result.asError!.error,
            result.asError!.stackTrace,
          );
        }
        return result.result!;
      },
    );

    if (!resp.isError && mounted) {
      Navigator.of(context).pop<PracticeFeedbackOutcome>(resp.result);
    }
  }

  Widget _pairRow(BuildContext context, PracticeExerciseChoice choice) {
    final theme = Theme.of(context);
    final eligibility = _eligibility(choice);
    final enabled = eligibility == PracticePairEligibility.flaggable;
    final selected = _selected == choice;

    final hint = switch (eligibility) {
      PracticePairEligibility.flaggable => null,
      PracticePairEligibility.userSetEmoji => L10n.of(
        context,
      ).practiceFeedbackUserSetEmoji,
      PracticePairEligibility.alreadyMatched => L10n.of(
        context,
      ).practiceFeedbackAlreadyMatched,
    };

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8.0),
        child: InkWell(
          borderRadius: BorderRadius.circular(8.0),
          onTap: enabled ? () => setState(() => _selected = choice) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        choice.form.form,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    Flexible(
                      child: Text(
                        choice.choiceContent,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
                if (hint != null) Text(hint, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FeedbackDialog(
      title: L10n.of(context).practiceFeedbackDialogTitle,
      onSubmit: _submit,
      extraContent: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4.0,
        children: [
          Text(
            L10n.of(context).practiceFeedbackSelectPair,
            textAlign: TextAlign.center,
          ),
          ...widget.activity.matchContent.choices.map(
            (choice) => _pairRow(context, choice),
          ),
        ],
      ),
    );
  }
}
