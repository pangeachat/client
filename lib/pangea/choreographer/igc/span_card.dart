import 'package:flutter/material.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/utils/bot_style.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/pangea/choreographer/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/igc/pangea_match_state_model.dart';
import 'package:fluffychat/pangea/choreographer/igc/pangea_match_status_enum.dart';
import 'package:fluffychat/pangea/choreographer/igc/span_choice_type_enum.dart';
import 'package:fluffychat/pangea/choreographer/igc/span_data_model.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_dialog.dart';
import '../../../widgets/matrix.dart';
import '../../common/widgets/choice_array.dart';

class SpanCard extends StatefulWidget {
  final PangeaMatchState match;
  final Choreographer choreographer;
  final VoidCallback showNextMatch;
  final Future Function(String) onFeedbackSubmitted;

  const SpanCard({
    super.key,
    required this.match,
    required this.choreographer,
    required this.showNextMatch,
    required this.onFeedbackSubmitted,
  });

  @override
  State<SpanCard> createState() => SpanCardState();
}

class SpanCardState extends State<SpanCard> {
  final ValueNotifier<AsyncState<String>> _feedbackState =
      ValueNotifier<AsyncState<String>>(const AsyncIdle<String>());

  final ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _feedbackState.dispose();
    scrollController.dispose();
    super.dispose();
  }

  SpanChoice? get _selectedChoice =>
      widget.match.updatedMatch.match.selectedChoice;

  void _showFeedbackForSelection(BuildContext context) {
    final selected = _selectedChoice;
    if (selected != null) {
      _feedbackState.value =
          AsyncLoaded<String>(selected.feedbackToDisplay(context));
    } else {
      _feedbackState.value = const AsyncIdle<String>();
    }
  }

  void _onChoiceSelect(int index) {
    widget.match.selectChoice(index);
    _showFeedbackForSelection(context);
    setState(() {});
  }

  void _updateMatch(PangeaMatchStatusEnum status) {
    try {
      widget.choreographer.igcController.updateMatch(
        widget.match,
        status,
      );
      widget.showNextMatch();
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        level: SentryLevel.warning,
        data: {
          "match": widget.match.toJson(),
        },
      );
      widget.choreographer.clearMatches(e);
      return;
    }
  }

  Future<void> _showFeedbackDialog() async {
    final resp = await showDialog(
      context: context,
      builder: (context) => FeedbackDialog(
        title: L10n.of(context).spanFeedbackTitle,
        onSubmit: (feedback) => Navigator.of(context).pop(feedback),
      ),
    );
    if (resp == null || resp.isEmpty) {
      return;
    }

    await widget.onFeedbackSubmitted(resp);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300.0,
      child: Column(
        children: [
          // Header row: Close, Type Label + BotFace, Flag
          SizedBox(
            height: 40.0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  color: Theme.of(context).iconTheme.color,
                  onPressed: () => _updateMatch(PangeaMatchStatusEnum.ignored),
                ),
                const Flexible(
                  child: Center(
                    child: BotFace(
                      width: 32.0,
                      expression: BotExpression.idle,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.flag_outlined),
                  color: Theme.of(context).iconTheme.color,
                  onPressed: _showFeedbackDialog,
                ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: scrollController,
              child: SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12.0,
                    horizontal: 24.0,
                  ),
                  child: Column(
                    spacing: 12.0,
                    children: [
                      ChoicesArray(
                        isLoading: false,
                        choices: widget.match.updatedMatch.match.choices
                            ?.map(
                              (e) => Choice(
                                text: e.value,
                                color: e.selected ? e.type.color : null,
                                isGold: e.type.isSuggestion,
                              ),
                            )
                            .toList(),
                        onPressed: (value, index) => _onChoiceSelect(index),
                        selectedChoiceIndex:
                            widget.match.updatedMatch.match.selectedChoiceIndex,
                        id: widget.match.hashCode.toString(),
                        langCode: MatrixState
                            .pangeaController.userController.userL2Code!,
                      ),
                      const SizedBox(),
                      _SpanCardFeedback(_feedbackState),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _SpanCardButtons(
            onAccept: () => _updateMatch(PangeaMatchStatusEnum.accepted),
            onIgnore: () => _updateMatch(PangeaMatchStatusEnum.ignored),
            selectedChoice: _selectedChoice,
          ),
        ],
      ),
    );
  }
}

class _SpanCardFeedback extends StatelessWidget {
  final ValueNotifier<AsyncState<String>> feedbackState;

  const _SpanCardFeedback(this.feedbackState);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ValueListenableBuilder(
          valueListenable: feedbackState,
          builder: (context, state, __) {
            return switch (state) {
              AsyncIdle<String>() => Text(
                  L10n.of(context).correctionDefaultPrompt,
                  style: BotStyle.text(context).copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              AsyncLoaded<String>(:final value) =>
                Text(value, style: BotStyle.text(context)),
              _ => const SizedBox.shrink(),
            };
          },
        ),
      ],
    );
  }
}

class _SpanCardButtons extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onIgnore;
  final SpanChoice? selectedChoice;

  const _SpanCardButtons({
    required this.onAccept,
    required this.onIgnore,
    required this.selectedChoice,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
      ),
      padding: const EdgeInsets.only(top: 12.0),
      child: Row(
        spacing: 10.0,
        children: [
          Expanded(
            child: Opacity(
              opacity: 0.8,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withAlpha(25),
                ),
                onPressed: onIgnore,
                child: Center(
                  child: Text(L10n.of(context).ignoreInThisText),
                ),
              ),
            ),
          ),
          Expanded(
            child: Opacity(
              opacity: selectedChoice != null ? 1.0 : 0.5,
              child: TextButton(
                onPressed: selectedChoice != null ? onAccept : null,
                style: TextButton.styleFrom(
                  backgroundColor: (selectedChoice?.color ??
                          Theme.of(context).colorScheme.primary)
                      .withAlpha(50),
                  side: selectedChoice != null
                      ? BorderSide(
                          color: selectedChoice!.color,
                          style: BorderStyle.solid,
                          width: 2.0,
                        )
                      : null,
                ),
                child: Text(L10n.of(context).replace),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
