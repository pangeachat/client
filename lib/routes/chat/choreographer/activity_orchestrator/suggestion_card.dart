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

  void _close() {
    widget.popupManager.close();
  }

  // TODO ORCHESTRATOR: add feedback mechanism
  // void _showFeedbackDialog() {}

  void _onChoiceSelected(OrchestratorSuggestion choice) {
    try {
      widget.controller.selectChoice(choice);
      setState(() {});
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          "choice": choice.toJson(),
          "suggestion": suggestionsModel?.suggestion.toJson(),
        },
      );
    }

    if (choice.type != OrchestratorSuggestionType.best) return;
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

    final selected = suggestionsModel.selectedChoice;
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
                choices: suggestionsModel.shuffledChoices.map((e) {
                  final isBest = e.type == OrchestratorSuggestionType.best;
                  final isSelected = e == selected;
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
                selectedChoiceIndex: selected == null
                    ? null
                    : suggestionsModel.shuffledChoices.indexOf(selected),
                getDisplayCopy: (value) => value.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
