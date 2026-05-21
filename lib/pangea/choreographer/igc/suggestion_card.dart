import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_controller.dart';
import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_suggestion.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/choice_array.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';

class SuggestionCard extends StatefulWidget {
  final String overlayKey;
  final OrchestratorController controller;

  const SuggestionCard({
    required this.overlayKey,
    required this.controller,
    super.key,
  });

  @override
  SuggestionCardState createState() => SuggestionCardState();
}

class SuggestionCardState extends State<SuggestionCard> {
  ActiveSuggestionModel? get suggestionsModel =>
      widget.controller.activeSuggestion;

  void _close() {
    MatrixState.pAnyState.closeOverlay(widget.overlayKey);
  }

  // void _showFeedbackDialog() {}

  void _onChoiceSelected(OrchestratorSuggestion choice) {
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
    }
    if (mounted) _close();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestionsModel = this.suggestionsModel;
    if (suggestionsModel == null) {
      return SizedBox();
    }

    return Container(
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
          SizedBox(
            height: 40.0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  color: theme.iconTheme.color,
                  onPressed: _close,
                ),
                Text(
                  L10n.of(context).suggestion,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.merge(
                    TextStyle(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                // IconButton(
                //   icon: const Icon(Icons.flag_outlined),
                //   color: theme.iconTheme.color,
                //   onPressed: _showFeedbackDialog,
                // ),
                SizedBox(height: 40.0, width: 40.0),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 12.0,
              horizontal: 24.0,
            ),
            child: ChoicesArray<OrchestratorSuggestion>(
              choices: suggestionsModel.shuffledChoices
                  .map((e) => Choice(value: e))
                  .toList(),
              onPressed: (value, index) => _onChoiceSelected(value),
              selectedChoiceIndex: null,
              getDisplayCopy: (value) => value.text,
            ),
          ),
        ],
      ),
    );
  }
}
