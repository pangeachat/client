import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/choice_array.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_suggestion.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/writing_assistance_popup.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/writing_asssitance_popup_manager.dart';

class SuggestionCard extends StatefulWidget {
  final String overlayKey;
  final OrchestratorController controller;
  final WritingAssistancePopupManager popupManager;

  const SuggestionCard({
    required this.overlayKey,
    required this.controller,
    required this.popupManager,
    super.key,
  });

  @override
  SuggestionCardState createState() => SuggestionCardState();
}

class SuggestionCardState extends State<SuggestionCard> {
  ActiveSuggestionModel? get suggestionsModel =>
      widget.controller.activeSuggestion;

  /// The learner's local selection, used to show correct/incorrect feedback.
  OrchestratorSuggestion? _selected;

  /// Stable shuffled order for the current suggestion. [shuffledChoices]
  /// reshuffles on every call, which would scramble the choice order (and the
  /// feedback) on each rebuild, so we shuffle once per suggestion.
  Object? _orderedFor;
  List<OrchestratorSuggestion> _orderedChoices = const [];

  List<OrchestratorSuggestion> _choicesFor(ActiveSuggestionModel model) {
    if (!identical(_orderedFor, model.suggestion)) {
      _orderedFor = model.suggestion;
      _orderedChoices = model.shuffledChoices;
      _selected = null;
    }
    return _orderedChoices;
  }

  void _close() {
    widget.popupManager.close();
  }

  // TODO ORCHESTRATOR: add feedback mechanism
  // void _showFeedbackDialog() {}

  void _onChoiceSelected(OrchestratorSuggestion choice) {
    setState(() => _selected = choice);

    // Only the recommended (best) option advances a goal. Accept it (which
    // drops its text into the composer) and dismiss after a beat so the learner
    // sees the green confirmation. A distractor is wrong: show it red, keep the
    // card open so they can try again, and do NOT accept it.
    if (choice.type != OrchestratorSuggestionType.best) return;

    try {
      widget.controller.selectChoice(choice);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          "choice": choice.toJson(),
          "suggestion": suggestionsModel?.suggestion.toJson(),
        },
      );
      return;
    }
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _close();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestionsModel = this.suggestionsModel;
    if (suggestionsModel == null) {
      return SizedBox();
    }

    return WritingAssistancePopup(
      widget.popupManager,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 350),
        padding: EdgeInsets.all(10.0),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(width: 2, color: theme.colorScheme.primary),
          borderRadius: const BorderRadius.all(Radius.circular(25)),
        ),
        child: Column(
          mainAxisSize: .min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: L10n.of(context).close,
                  icon: const Icon(Icons.close),
                  color: theme.iconTheme.color,
                  onPressed: _close,
                ),
                Flexible(
                  child: Text(
                    L10n.of(context).suggestion,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.merge(
                      TextStyle(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                // TODO ORCHESTRATOR: add feedback mechanism
                // IconButton(
                //   icon: const Icon(Icons.flag_outlined),
                //   color: theme.iconTheme.color,
                //   onPressed: _showFeedbackDialog,
                // ),
                SizedBox(height: 40.0, width: 40.0),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 12.0,
                horizontal: 24.0,
              ),
              child: ChoicesArray<OrchestratorSuggestion>(
                choices: _choicesFor(suggestionsModel).map((e) {
                  final isBest = e.type == OrchestratorSuggestionType.best;
                  final isSelected = _selected == e;
                  return Choice(
                    value: e,
                    // Match the IGC SpanCard scheme: green for the correct
                    // (best) option, red for a distractor.
                    color: isSelected
                        ? (isBest ? Colors.green : Colors.red)
                        : null,
                    isGold: isBest,
                  );
                }).toList(),
                onPressed: (value, index) => _onChoiceSelected(value),
                selectedChoiceIndex: _selected == null
                    ? null
                    : _choicesFor(suggestionsModel).indexOf(_selected!),
                getDisplayCopy: (value) => value.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
