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
import 'package:fluffychat/routes/chat/choreographer/igc/span_data_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/writing_assistance_popup.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/writing_asssitance_popup_manager.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_disabled_popup.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SpanCard extends StatefulWidget {
  final WritingAssistancePopupManager controller;
  final double maxHeight;

  const SpanCard({
    super.key,
    required this.controller,
    required this.maxHeight,
  });

  @override
  State<SpanCard> createState() => SpanCardState();
}

class SpanCardState extends State<SpanCard> {
  final ScrollController scrollController = ScrollController();

  double? _previousOffset;
  Offset _slideFrom = const Offset(0.1, 0); // default slide from right

  /// Listen mode: while on, tapping a choice plays it and selects nothing.
  ///
  /// Belongs to the match being shown — advancing to another one turns it off,
  /// so a learner can never carry an invisible mode into a choice they meant
  /// to pick. See writing-assistance.instructions.md.
  bool _listening = false;

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

    if (mounted) setState(() => _listening = false);
  }

  /// Turn Listen mode on or off.
  ///
  /// Choice audio is gated by the audio section of learning settings, and a
  /// mode whose whole purpose is audio must not be enterable while that gate
  /// is shut — it would be a toggle that produces silence. The toggle is an
  /// explicit audio affordance, so it says so the way the others do.
  void _toggleListening(String targetId) {
    if (!_listening && !ToolSetting.audioChoices.enabled) {
      TtsDisabledPopup.show(context, targetId, ToolSetting.audioChoices);
      return;
    }
    setState(() => _listening = !_listening);
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
          if (match == null) return const SizedBox.shrink();

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

          // Size to content so all choices are visible without scrolling,
          // up to the available space above the input field.
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
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
                Flexible(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
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
                        roomId: _choreographer.room.id,
                        listening: _listening,
                        onToggleListening: _toggleListening,
                      ),
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

  /// The room being typed in, passed through to [ChoicesArray] so a tapped
  /// choice's audio is counted against it.
  final String roomId;

  /// Whether Listen mode is on, in which case a tapped choice is only spoken.
  final bool listening;

  /// Takes the id of the transform target the "audio is off" popup anchors to,
  /// which is this content's toggle.
  final void Function(String) onToggleListening;

  const _MatchContent({
    super.key,
    required this.match,
    required this.scrollController,
    required this.onChoiceSelect,
    required this.onUpdateMatch,
    required this.roomId,
    required this.listening,
    required this.onToggleListening,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOpen = match.updatedMatch.status.isOpen;
    final currentMatch = match.updatedMatch.match;
    final descriptionText =
        currentMatch.bestChoice?.feedback ??
        currentMatch.type.defaultPrompt(context);

    // Per match, so the crossfade between two matches never has two subtrees
    // holding the same global key.
    final listenTargetId = 'wa-listen-${match.hashCode}';
    final listenLink = MatrixState.pAnyState.layerLinkAndKey(listenTargetId);

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
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
              if (isOpen)
                Semantics(
                  toggled: listening,
                  child: CompositedTransformTarget(
                    link: listenLink.link,
                    child: KeyedSubtree(
                      key: listenLink.key,
                      child: TextButton.icon(
                        onPressed: () => onToggleListening(listenTargetId),
                        icon: const Icon(Icons.headphones, size: 18.0),
                        label: Text(L10n.of(context).listen),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          backgroundColor: listening
                              ? theme.colorScheme.primary
                              : null,
                          foregroundColor: listening
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurfaceVariant,
                          shape: StadiumBorder(
                            side: BorderSide(
                              color: listening
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              isOpen
                  ? ChoicesArray<SpanChoice>(
                      choices: currentMatch.choices?.map((e) {
                        return Choice<SpanChoice>(
                          value: e,
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
                      // Writing assistance always runs against the room being
                      // typed in, so the choice audio it plays is that room's
                      // listening.
                      roomId: roomId,
                      id: match.hashCode.toString(),
                      langCode: MatrixState
                          .pangeaController
                          .userController
                          .userL2Code!,
                      enabled: !currentMatch.isSelectedChoiceCorrection,
                      getDisplayCopy: (choice) => choice.value,
                      listenMode: listening,
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
              if (isOpen && listening)
                Text(
                  L10n.of(context).listenModeDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
