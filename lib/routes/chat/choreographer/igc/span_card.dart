import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/features/instructions/instructions_inline_tooltip.dart';
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

  /// Listen First: while on, one tap on a choice plays it and a second tap
  /// selects it.
  ///
  /// Seeded from the learner's stored preference and written back on every
  /// toggle, so it survives the card advancing and the app restarting — being
  /// an ear-first learner is not a property of one correction. See
  /// writing-assistance.instructions.md.
  late bool _listenFirst;

  Choreographer get _choreographer => widget.controller.choreographer;

  @override
  void initState() {
    super.initState();
    _listenFirst = ToolSetting.listenFirst.enabled;
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
  }

  /// Turn Listen First on or off, and remember it.
  ///
  /// Choice audio is gated by the audio section of learning settings, and a
  /// mode whose whole purpose is audio must not be enterable while that gate
  /// is shut — it would be a toggle that produces silence. The toggle is an
  /// explicit audio affordance, so it says so the way the others do, and
  /// nothing is stored: the learner has not chosen the mode, they have been
  /// told why they can't have it yet.
  void _toggleListenFirst(String targetId) {
    if (!_listenFirst && !ToolSetting.audioChoices.enabled) {
      TtsDisabledPopup.show(context, targetId, ToolSetting.audioChoices);
      return;
    }
    setState(() => _listenFirst = !_listenFirst);
    MatrixState.pangeaController.userController.setListenFirst(_listenFirst);
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

          // Size to content so all choices are visible without scrolling,
          // up to the available space above the input field.
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
            child: Column(
              mainAxisSize: .min,
              children: [
                SpanCardHeader(
                  title: match.updatedMatch.match.type.displayName(context),
                  // An accepted match shows a diff and an undo, not choices,
                  // so there is nothing there to listen to.
                  showListenFirst: match.updatedMatch.status.isOpen,
                  listenFirst: _listenFirst,
                  onToggleListenFirst: _toggleListenFirst,
                  onFeedback: _showFeedbackDialog,
                  onClose: widget.controller.close,
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
                        listenFirst: _listenFirst,
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

  /// Whether Listen First is on, in which case one tap on a choice only plays
  /// it and a second tap selects it.
  final bool listenFirst;

  const _MatchContent({
    super.key,
    required this.match,
    required this.scrollController,
    required this.onChoiceSelect,
    required this.onUpdateMatch,
    required this.roomId,
    required this.listenFirst,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
                textAlign: TextAlign.center,
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
                      listenFirstMode: listenFirst,
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
              if (isOpen && listenFirst)
                const InstructionsInlineTooltip(
                  instructionsEnum: InstructionsEnum.listenFirst,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card's two per-match actions, as the overflow menu names them.
enum SpanCardAction { listenFirst, feedback }

/// The card's header: close on the left, the match's category in the middle,
/// and the card's two actions on the right.
///
/// The actions collapse into a single overflow menu when the title cannot sit
/// beside them at full width. The category name is what the learner is reading
/// the card for, and it is the part that grows — "Subject Verb Agreement" on a
/// phone leaves no room for two icons — so the icons yield to it rather than
/// the other way around.
class SpanCardHeader extends StatelessWidget {
  final String title;

  /// Whether this match has choices, and so anything Listen First applies to.
  final bool showListenFirst;
  final bool listenFirst;

  /// Takes the id of the transform target the "audio is off" popup anchors to,
  /// which is whichever control is currently showing Listen First.
  final void Function(String) onToggleListenFirst;
  final VoidCallback onFeedback;
  final VoidCallback onClose;

  const SpanCardHeader({
    super.key,
    required this.title,
    required this.showListenFirst,
    required this.listenFirst,
    required this.onToggleListenFirst,
    required this.onFeedback,
    required this.onClose,
  });

  /// One anchor for both layouts: only one of them is ever built.
  static const _listenTargetId = 'wa-listen-first';

  /// The width an [IconButton] takes at the default visual density.
  static const _iconButtonWidth = 48.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final titleStyle = theme.textTheme.titleLarge?.merge(
      TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Measured, not guessed at a breakpoint: the same header fits two
        // icons for "Spelling" and cannot for "Subject Verb Agreement" at the
        // identical width, and a learner scaling their text up moves that line
        // again.
        final painter = TextPainter(
          text: TextSpan(text: title, style: titleStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final titleWidth = painter.width;
        painter.dispose();

        // Close, plus either both actions or the single menu that replaces
        // them. With only the flag to place there is nothing to collapse —
        // one icon always fits beside a title that can ellipsize, and a
        // one-item overflow menu is a worse place to keep it.
        final expanded =
            !showListenFirst ||
            titleWidth <= constraints.maxWidth - _iconButtonWidth * 3;

        return Row(
          children: [
            IconButton(
              tooltip: l10n.close,
              icon: const Icon(Icons.close),
              color: theme.iconTheme.color,
              onPressed: onClose,
            ),
            Expanded(
              child: Center(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
            ),
            if (expanded) ...[
              if (showListenFirst) _listenFirstButton(context),
              IconButton(
                tooltip: l10n.feedbackButton,
                icon: const Icon(Icons.flag_outlined),
                color: theme.iconTheme.color,
                onPressed: onFeedback,
              ),
            ] else
              _overflowMenu(context),
          ],
        );
      },
    );
  }

  Widget _listenFirstButton(BuildContext context) {
    final theme = Theme.of(context);
    final link = MatrixState.pAnyState.layerLinkAndKey(_listenTargetId);

    return Semantics(
      toggled: listenFirst,
      child: CompositedTransformTarget(
        link: link.link,
        child: KeyedSubtree(
          key: link.key,
          child: IconButton(
            tooltip: L10n.of(context).listenFirst,
            isSelected: listenFirst,
            icon: const Icon(Icons.headphones_outlined),
            selectedIcon: const Icon(Icons.headphones),
            style: IconButton.styleFrom(
              backgroundColor: listenFirst
                  ? theme.colorScheme.primaryContainer
                  : null,
              foregroundColor: listenFirst
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.iconTheme.color,
            ),
            onPressed: () => onToggleListenFirst(_listenTargetId),
          ),
        ),
      ),
    );
  }

  Widget _overflowMenu(BuildContext context) {
    final l10n = L10n.of(context);
    final link = MatrixState.pAnyState.layerLinkAndKey(_listenTargetId);

    return CompositedTransformTarget(
      link: link.link,
      child: KeyedSubtree(
        key: link.key,
        child: PopupMenuButton<SpanCardAction>(
          useRootNavigator: true,
          // An unnamed PopupMenuButton falls back to the framework default,
          // and the a11y floor check does not cover it.
          tooltip: l10n.moreOptions,
          icon: const Icon(Icons.more_vert),
          onSelected: (action) {
            switch (action) {
              case SpanCardAction.listenFirst:
                onToggleListenFirst(_listenTargetId);
              case SpanCardAction.feedback:
                onFeedback();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem<SpanCardAction>(
              value: SpanCardAction.listenFirst,
              child: Semantics(
                checked: listenFirst,
                child: Row(
                  children: [
                    Icon(
                      listenFirst
                          ? Icons.headphones
                          : Icons.headphones_outlined,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(l10n.listenFirst)),
                    if (listenFirst) const Icon(Icons.check, size: 18.0),
                  ],
                ),
              ),
            ),
            PopupMenuItem<SpanCardAction>(
              value: SpanCardAction.feedback,
              child: Row(
                children: [
                  const Icon(Icons.flag_outlined),
                  const SizedBox(width: 12),
                  Text(l10n.feedbackButton),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
