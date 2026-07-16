import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/choice_array.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_dialog.dart';
import 'package:fluffychat/routes/chat/choreographer/assistance_state_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/choreographer.dart';
import 'package:fluffychat/routes/chat/choreographer/choreographer_state_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_state_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_status_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/replacement_type_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_choice_type_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/writing_assistance_popup.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/writing_asssitance_popup_manager.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SpanCard extends StatefulWidget {
  final WritingAssistancePopupManager controller;

  const SpanCard({super.key, required this.controller});

  @override
  State<SpanCard> createState() => SpanCardState();
}

class SpanCardState extends State<SpanCard> {
  final ScrollController scrollController = ScrollController();

  double? _previousOffset;
  Offset _slideFrom = const Offset(0.1, 0); // default slide from right

  Choreographer get _choreographer => widget.controller.choreographer;

  @override
  void initState() {
    super.initState();
    _activeMatch.addListener(_onActiveMatchUpdate);
    _choreographer.addListener(_onAssistanceStateChange);
  }

  @override
  void dispose() {
    scrollController.dispose();
    _activeMatch.removeListener(_onActiveMatchUpdate);
    _choreographer.removeListener(_onAssistanceStateChange);
    super.dispose();
  }

  ValueNotifier<PangeaMatchState?> get _activeMatch =>
      _choreographer.igcController.activeMatch;

  Future<void> _onAssistanceStateChange() async {
    if (_choreographer.assistanceState != AssistanceStateEnum.fetched) {
      await widget.controller.close();
    }
  }

  Future<void> _onActiveMatchUpdate() async {
    final activeMatch = _activeMatch.value;

    if (activeMatch == null) {
      await widget.controller.close();
      return;
    }

    if (mounted) setState(() {});
  }

  Future<void> _onChoiceSelect(
    PangeaMatchState match,
    int index,
    PangeaMatchStatusEnum status,
  ) async {
    final choice = match.updatedMatch.match.choices?[index];
    final correct = choice?.type.isSuggestion == true;
    final selected = choice?.selected == true;

    match.selectChoice(index);
    setState(() {});

    if (!correct && !selected) return;
    await Future.delayed(
      Duration(milliseconds: 600),
      () => _updateMatch(match, status),
    );
  }

  Future<void> _updateMatch(
    PangeaMatchState match,
    PangeaMatchStatusEnum status,
  ) async {
    try {
      final igc = _choreographer.igcController;
      igc.updateMatchStatus(match, status);
      if (!status.isOpen) {
        igc.hasOpenMatches ? igc.showNextMatchToShow() : igc.clearMatchToShow();
      }
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        level: SentryLevel.warning,
        data: {"match": match.toJson()},
      );
      _choreographer.clearMatches(e);
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

    await widget.controller.onFeedbackSubmitted(resp);
  }

  @override
  Widget build(BuildContext context) {
    return WritingAssistancePopup(
      widget.controller,
      child: StreamBuilder(
        stream: _choreographer.igcController.matchUpdateStream.stream,
        builder: (context, _) {
          final match = _activeMatch.value;
          if (match == null) return SizedBox(height: 200.0);

          final newOffset = match.updatedMatch.match.offset.toDouble();
          if (_previousOffset != null) {
            if (newOffset < _previousOffset!) {
              // Moving backward → slide from left
              _slideFrom = const Offset(-0.1, 0);
            } else if (newOffset > _previousOffset!) {
              // Moving forward → slide from right
              _slideFrom = const Offset(0.1, 0);
            }
          }
          _previousOffset = newOffset;
          final theme = Theme.of(context);

          return SizedBox(
            height: 200.0,
            child: Column(
              mainAxisSize: .min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: L10n.of(context).close,
                      icon: const Icon(Icons.close),
                      color: theme.iconTheme.color,
                      onPressed: widget.controller.close,
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          match.updatedMatch.match.type.displayName(context),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.merge(
                            TextStyle(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: L10n.of(context).feedbackButton,
                      icon: const Icon(Icons.flag_outlined),
                      color: theme.iconTheme.color,
                      onPressed: _showFeedbackDialog,
                    ),
                  ],
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) {
                      final slideAnimation = Tween<Offset>(
                        begin: _slideFrom,
                        end: Offset.zero,
                      ).animate(animation);

                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: slideAnimation,
                          child: child,
                        ),
                      );
                    },
                    child: _MatchContent(
                      key: ValueKey(match.hashCode),
                      match: match,
                      scrollController: scrollController,
                      onChoiceSelect: _onChoiceSelect,
                      onUpdateMatch: _updateMatch,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MatchContent extends StatelessWidget {
  final PangeaMatchState match;
  final ScrollController scrollController;
  final Future<void> Function(PangeaMatchState, int, PangeaMatchStatusEnum)
  onChoiceSelect;
  final Future<void> Function(PangeaMatchState, PangeaMatchStatusEnum)
  onUpdateMatch;

  const _MatchContent({
    super.key,
    required this.match,
    required this.scrollController,
    required this.onChoiceSelect,
    required this.onUpdateMatch,
  });

  @override
  Widget build(BuildContext context) {
    final isOpen = match.updatedMatch.status.isOpen;
    final currentMatch = match.updatedMatch.match;
    final descriptionText =
        currentMatch.bestChoice?.feedback ??
        currentMatch.type.defaultPrompt(context);

    return Scrollbar(
      controller: scrollController,
      child: SingleChildScrollView(
        controller: scrollController,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 24.0),
          child: Column(
            spacing: 12.0,
            children: [
              Text(
                descriptionText,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
              isOpen
                  ? ChoicesArray(
                      choices: currentMatch.choices?.map((e) {
                        return Choice(
                          value: e.value,
                          color: e.selected ? e.type.color : null,
                          isGold: e.type.isSuggestion,
                        );
                      }).toList(),
                      onPressed: (value, index) => onChoiceSelect(
                        match,
                        index,
                        PangeaMatchStatusEnum.accepted,
                      ),
                      selectedChoiceIndex: currentMatch.selectedChoiceIndex,
                      id: match.hashCode.toString(),
                      langCode: MatrixState
                          .pangeaController
                          .userController
                          .userL2Code!,
                      enabled: !currentMatch.isSelectedChoiceCorrection,
                    )
                  : Row(
                      spacing: 16.0,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Wrap(
                            spacing: 8.0,
                            runSpacing: 4.0,
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(match.originalMatch.match.errorSpan),
                              const Icon(Icons.arrow_forward, size: 16.0),
                              Text(
                                match
                                        .updatedMatch
                                        .match
                                        .selectedChoice
                                        ?.value ??
                                    L10n.of(context).nothingFound,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: L10n.of(context).undo,
                          icon: const Icon(Symbols.undo),
                          onPressed: () =>
                              onUpdateMatch(match, PangeaMatchStatusEnum.undo),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
