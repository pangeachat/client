import 'package:flutter/material.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/utils/bot_style.dart';
import 'package:fluffychat/pangea/choreographer/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/igc/pangea_match_state_model.dart';
import 'package:fluffychat/pangea/choreographer/igc/pangea_match_status_enum.dart';
import 'package:fluffychat/pangea/choreographer/igc/span_choice_type_enum.dart';
import 'package:fluffychat/pangea/choreographer/igc/span_data_model.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import '../../../widgets/matrix.dart';
import '../../common/widgets/choice_array.dart';

class SpanCard extends StatefulWidget {
  final PangeaMatchState match;
  final Choreographer choreographer;
  final VoidCallback showNextMatch;

  const SpanCard({
    super.key,
    required this.match,
    required this.choreographer,
    required this.showNextMatch,
  });

  @override
  State<SpanCard> createState() => SpanCardState();
}

class SpanCardState extends State<SpanCard> {
  bool _loadingChoices = true;
  final ValueNotifier<AsyncState<String>> _feedbackState =
      ValueNotifier<AsyncState<String>>(const AsyncIdle<String>());

  final ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchChoices();
  }

  @override
  void dispose() {
    _feedbackState.dispose();
    scrollController.dispose();
    super.dispose();
  }

  List<SpanChoice>? get _choices => widget.match.updatedMatch.match.choices;

  SpanChoice? get _selectedChoice =>
      widget.match.updatedMatch.match.selectedChoice;

  String? get _selectedFeedback => _selectedChoice?.feedback;

  Future<void> _fetchChoices() async {
    if (_choices != null && _choices!.length > 1) {
      setState(() => _loadingChoices = false);
      return;
    }

    setState(() => _loadingChoices = true);

    try {
      await widget.choreographer.igcController.fetchSpanDetails(
        match: widget.match,
      );

      if (_choices == null || _choices!.isEmpty) {
        widget.choreographer.clearMatches(
          'No choices available for span ${widget.match.updatedMatch.match.message}',
        );
      }
    } catch (e) {
      widget.choreographer.clearMatches(e);
    } finally {
      if (mounted) {
        setState(() => _loadingChoices = false);
      }
    }
  }

  Future<void> _fetchFeedback() async {
    if (_selectedFeedback != null) {
      _feedbackState.value = AsyncLoaded<String>(_selectedFeedback!);
      return;
    }

    try {
      _feedbackState.value = const AsyncLoading<String>();
      await widget.choreographer.igcController.fetchSpanDetails(
        match: widget.match,
        force: true,
      );

      if (!mounted) return;
      if (_selectedFeedback != null) {
        _feedbackState.value = AsyncLoaded<String>(_selectedFeedback!);
      } else {
        _feedbackState.value = AsyncError<String>(
          L10n.of(context).failedToLoadFeedback,
        );
      }
    } catch (e) {
      if (mounted) {
        _feedbackState.value = AsyncError<String>(e);
      }
    }
  }

  void _onChoiceSelect(int index) {
    final selected = _choices![index];
    widget.match.selectChoice(index);

    _feedbackState.value = selected.feedback != null
        ? AsyncLoaded<String>(selected.feedback!)
        : const AsyncIdle<String>();

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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300.0,
      child: Column(
        children: [
          Expanded(
            child: Scrollbar(
              controller: scrollController,
              child: Container(
                decoration:
                    BoxDecoration(border: Border.all(color: Colors.green)),
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
                          isLoading: _loadingChoices,
                          choices: widget.match.updatedMatch.match.choices
                              ?.map(
                                (e) => Choice(
                                  text: e.value,
                                  color: e.selected ? e.type.color : null,
                                  isGold: e.type.name == 'bestCorrection',
                                ),
                              )
                              .toList(),
                          onPressed: (value, index) => _onChoiceSelect(index),
                          selectedChoiceIndex: widget
                              .match.updatedMatch.match.selectedChoiceIndex,
                          id: widget.match.hashCode.toString(),
                          langCode: MatrixState
                              .pangeaController.userController.userL2Code!,
                        ),
                        const SizedBox(),
                        _SpanCardFeedback(
                          _selectedChoice != null,
                          _fetchFeedback,
                          _feedbackState,
                        ),
                      ],
                    ),
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
  final bool hasSelectedChoice;
  final VoidCallback fetchFeedback;
  final ValueNotifier<AsyncState<String>> feedbackState;

  const _SpanCardFeedback(
    this.hasSelectedChoice,
    this.fetchFeedback,
    this.feedbackState,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ValueListenableBuilder(
          valueListenable: feedbackState,
          builder: (context, state, __) {
            return switch (state) {
              AsyncIdle<String>() => hasSelectedChoice
                  ? IconButton(
                      onPressed: fetchFeedback,
                      icon: const Icon(Icons.lightbulb_outline, size: 24),
                    )
                  : Text(
                      L10n.of(context).correctionDefaultPrompt,
                      style: BotStyle.text(context).copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
              AsyncLoading<String>() => const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(),
                ),
              AsyncError<String>(:final error) =>
                ErrorIndicator(message: error.toString()),
              AsyncLoaded<String>(:final value) =>
                Text(value, style: BotStyle.text(context)),
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
