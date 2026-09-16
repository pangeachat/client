import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/choice_array.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/active_suggestion_model.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_feedback_dialog.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_suggestion.dart';
import 'package:fluffychat/routes/chat/choreographer/choreographer.dart';
import 'package:fluffychat/routes/chat/choreographer/choreographer_state_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/writing_assistance_popup.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/writing_asssitance_popup_manager.dart';

class SuggestionCard extends StatefulWidget {
  final OrchestratorController controller;
  final WritingAssistancePopupManager popupManager;

  /// The height available in the shared popup slot above the input field. The
  /// card sizes to its content up to this, and only then scrolls.
  final double maxHeight;

  const SuggestionCard({
    required this.controller,
    required this.popupManager,
    required this.maxHeight,
    super.key,
  });

  @override
  SuggestionCardState createState() => SuggestionCardState();
}

class SuggestionCardState extends State<SuggestionCard> {
  ActiveSuggestionModel? get suggestionsModel =>
      widget.controller.activeSuggestion;

  StreamSubscription<ActiveSuggestionModel?>? _suggestionSubscription;

  Choreographer get _choreographer => widget.popupManager.choreographer;

  @override
  void initState() {
    super.initState();
    _choreographer.addListener(_onAssistanceStateChange);
    // Under re-fire the active suggestion can change while the card is open:
    // rebuild on replace (taps never hit a swapped-out model), close on clear.
    _suggestionSubscription = widget.controller.suggestionStream.stream.listen((
      suggestion,
    ) {
      if (!mounted) return;
      if (suggestion == null) {
        _close();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _suggestionSubscription?.cancel();
    _choreographer.removeListener(_onAssistanceStateChange);
    // Closing the card without accepting releases the mid-interaction pin
    // (a tapped distractor otherwise blocks every future replacement).
    final model = widget.controller.activeSuggestion;
    if (model != null &&
        model.acceptedChoice == null &&
        model.selectedChoice != null) {
      widget.controller.resetSuggestionState();
    }
    super.dispose();
  }

  void _close() {
    widget.popupManager.close();
  }

  /// Follows the state that offered the card: the learner's first typed
  /// character leaves the suggesting states, and the card goes with it (#8953).
  /// Left open, it would sit over the learner's own message and hold the single
  /// popup slot the span card needs when they press check.
  void _onAssistanceStateChange() {
    if (_choreographer.assistanceState.keepsSuggestionCardOpen) return;
    _close();
  }

  /// Internal reviewer feedback (staging only). Records the objection against
  /// the stored orchestrator turn and regenerates it there; nothing in this
  /// room changes, so the card is left exactly as it is and the learner can
  /// still send the suggestion they were shown.
  Future<void> _showFeedbackDialog() async {
    final model = suggestionsModel;
    if (model == null) return;
    await showOrchestratorFeedbackDialog(
      context: context,
      roomId: widget.controller.room.id,
      basedOnEventId: model.basedOnEventId,
      ownRoleId: model.suggestion.roleId,
      goalCompletion: model.goalCompletion,
      activityPlan: widget.controller.room.activityPlan,
    );
  }

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
    final selected = suggestionsModel?.selectedChoice;
    // The empty case goes INSIDE the popup wrapper, never in place of it, the
    // way SpanCard does it. Disposing that wrapper is the only thing that ever
    // tells the manager this card is gone, so a build that returns without one
    // leaves the manager certain a card is up forever (#8980).
    return WritingAssistancePopup(
      widget.popupManager,
      child: suggestionsModel == null
          ? const SizedBox.shrink()
          // Width and chrome come from the shared overlay container the span
          // card already uses; the card only claims the height it needs, up to
          // the space above the input field (#9074).
          : ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.maxHeight),
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
                      // Staging only: an instrument for the team, not a
                      // learner-facing feature. The spacer keeps the title
                      // centred against the close button where it is absent.
                      if (Environment.isStagingEnvironment)
                        IconButton(
                          tooltip: L10n.of(context).orchestratorFeedbackTooltip,
                          icon: const Icon(Icons.flag_outlined),
                          color: theme.iconTheme.color,
                          onPressed: _showFeedbackDialog,
                        )
                      else
                        const SizedBox(height: 40.0, width: 40.0),
                    ],
                  ),
                  // Scrolls only once the choices outgrow the slot, the way
                  // the span card's content does.
                  Flexible(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12.0,
                          horizontal: 24.0,
                        ),
                        child: ChoicesArray<OrchestratorSuggestion>(
                          choices: suggestionsModel.shuffledChoices.map((e) {
                            final isBest =
                                e.type == OrchestratorSuggestionType.best;
                            final isSelected = e == selected;
                            return Choice(
                              value: e,
                              // Match the IGC SpanCard scheme: the success
                              // mark for the correct (best) option, the error
                              // mark for a distractor.
                              color: isSelected
                                  ? (isBest
                                        ? Theme.of(
                                            context,
                                          ).pangea.successGraphic
                                        : Theme.of(context).pangea.errorGraphic)
                                  : null,
                              isGold: isBest,
                            );
                          }).toList(),
                          onPressed: (value, index) => _onChoiceSelected(value),
                          selectedChoiceIndex: selected == null
                              ? null
                              : suggestionsModel.shuffledChoices.indexOf(
                                  selected,
                                ),
                          // The orchestrator is per activity room, so a suggestion's
                          // audio belongs to the room the activity runs in.
                          roomId: widget.controller.room.id,
                          getDisplayCopy: (value) => value.text,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
