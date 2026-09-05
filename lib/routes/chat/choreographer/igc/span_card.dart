import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/features/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
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

  /// Turn off (or back on) writing assistance running itself on every message.
  ///
  /// The same `autoIGC` toggle the learning settings page owns — a learner who
  /// has just been handed a card they did not ask for should be able to stop
  /// that from here, without hunting for the setting.
  void _toggleAutoIGC() {
    final enabled = ToolSetting.autoIGC.enabled;
    MatrixState.pangeaController.userController.updateProfile(
      (profile) => profile.copyWith(
        toolSettings: profile.toolSettings.copyWith(autoIGC: !enabled),
      ),
    );
    setState(() {});
  }

  void _openLearningSettings() {
    final router = GoRouter.of(context);
    final target = WorkspaceNav.openSettings(
      GoRouterState.of(context).uri,
      page: 'learning',
      // On a narrow layout the settings panel and the chat cannot share the
      // width, so the sections close behind it the way every other entry
      // point into this page does.
      closeSections: !FluffyThemes.isColumnMode(context),
      seatMenu: false,
    );

    // The overflow menu pops its own route when an item is chosen, and it is
    // pushed on the root navigator — the same one GoRouter builds its pages
    // on. Navigating in that frame lets the menu's pop take the page the
    // router just pushed, so the panel opens and closes again in one motion.
    // Resolved up front because this context goes away with the card.
    WidgetsBinding.instance.addPostFrameCallback((_) => router.go(target));
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
    // No Flutter tooltip may ever open inside this card.
    //
    // The card is mounted in an overlay that FOLLOWS the input field, so every
    // control in it sits under a RenderFollowerLayer. Tooltip positions itself
    // with `localToGlobal(..., ancestor: overlay)`, and computing a paint
    // transform across a follower is not reliable — the framework asserts
    // "The paint transform cannot be reliably computed because of
    // RenderFollowerLayer(s)". It throws on every frame the pointer rests on
    // the control, which the learner sees as a flashing red screen (#8823).
    //
    // This disables the tooltip OVERLAY, and with it the semantics `tooltip`
    // the Tooltip would otherwise contribute — measured, not assumed: under
    // TooltipVisibility a button's semantics tooltip reads empty. So every
    // control in the card names itself with an icon `semanticLabel:` — the
    // shape measured to survive the suppression — and `tooltip:` stays on each
    // button for the a11y floor check and for the day this wrapper can go
    // away. Wrapped at the root so a control added later is covered too, but a
    // NEW control still needs its own semanticLabel or it will be unnamed.
    return TooltipVisibility(
      visible: false,
      child: WritingAssistancePopup(
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
                    // Per match. The id keys a GlobalKey that PangeaAnyState
                    // caches forever, so a constant one is claimed by every
                    // header that ever mounts — and two live at once whenever
                    // one card is torn down while its replacement is building,
                    // which is a duplicate-GlobalKey throw on every rebuild.
                    targetId: 'wa-listen-${match.hashCode}',
                    title: match.updatedMatch.match.type.displayName(context),
                    // An accepted match shows a diff and an undo, not choices,
                    // so there is nothing there to listen to.
                    showListenFirst: match.updatedMatch.status.isOpen,
                    listenFirst: _listenFirst,
                    autoIGC: ToolSetting.autoIGC.enabled,
                    onToggleListenFirst: _toggleListenFirst,
                    onToggleAutoIGC: _toggleAutoIGC,
                    onFeedback: _showFeedbackDialog,
                    onLearningSettings: _openLearningSettings,
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
                        Semantics(
                          label: L10n.of(context).undo,
                          child: IconButton(
                            tooltip: L10n.of(context).undo,
                            icon: const Icon(Symbols.undo),
                            onPressed: () => onUpdateMatch(
                              match,
                              PangeaMatchStatusEnum.undo,
                            ),
                          ),
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

/// The actions the card's overflow menu offers.
enum SpanCardAction { listenFirst, autoIGC, feedback, learningSettings }

/// The card's header: close on the left, the match's category in the middle,
/// and on the right the Listen First toggle plus an overflow menu.
///
/// Listen First is the only action with a place in the header itself, because
/// it is the one a learner flips mid-card; everything else — the auto-run
/// toggle, reporting the content, the full settings page — is a trip out of
/// the card and belongs behind the menu. When the category name cannot sit
/// beside both, Listen First folds into the menu too: the name is what the
/// learner opened the card to read, and it is the part that grows.
class SpanCardHeader extends StatelessWidget {
  /// Anchors the "audio is off" popup, and keys the GlobalKey that positions
  /// it. Must be unique to the match on screen — see the call site.
  final String targetId;
  final String title;

  /// Whether this match has choices, and so anything Listen First applies to.
  final bool showListenFirst;
  final bool listenFirst;

  /// Whether writing assistance runs itself on every sent message.
  final bool autoIGC;

  /// Takes the id of the transform target the "audio is off" popup anchors to,
  /// which is whichever control is currently showing Listen First.
  final void Function(String) onToggleListenFirst;
  final VoidCallback onToggleAutoIGC;
  final VoidCallback onFeedback;
  final VoidCallback onLearningSettings;
  final VoidCallback onClose;

  const SpanCardHeader({
    super.key,
    required this.targetId,
    required this.title,
    required this.showListenFirst,
    required this.listenFirst,
    required this.autoIGC,
    required this.onToggleListenFirst,
    required this.onToggleAutoIGC,
    required this.onFeedback,
    required this.onLearningSettings,
    required this.onClose,
  });

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
        // Measured, not guessed at a breakpoint: the same header fits the
        // toggle for "Spelling" and cannot for "Subject Verb Agreement" at the
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

        // Close on the left, the menu always on the right, and Listen First
        // between them only when the title can spare the width.
        final inlineListenFirst =
            showListenFirst &&
            titleWidth <= constraints.maxWidth - _iconButtonWidth * 3;

        return Row(
          children: [
            IconButton(
              tooltip: l10n.close,
              icon: Icon(Icons.close, semanticLabel: l10n.close),
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
            if (inlineListenFirst) _listenFirstButton(context),
            _overflowMenu(context, inMenuListenFirst: !inlineListenFirst),
          ],
        );
      },
    );
  }

  Widget _listenFirstButton(BuildContext context) {
    final theme = Theme.of(context);
    final link = MatrixState.pAnyState.layerLinkAndKey(targetId);

    final name = L10n.of(context).listenFirst;
    return Semantics(
      toggled: listenFirst,
      child: CompositedTransformTarget(
        link: link.link,
        child: KeyedSubtree(
          key: link.key,
          child: IconButton(
            tooltip: name,
            isSelected: listenFirst,
            icon: Icon(Icons.headphones_outlined, semanticLabel: name),
            selectedIcon: Icon(Icons.headphones, semanticLabel: name),
            style: IconButton.styleFrom(
              backgroundColor: listenFirst
                  ? theme.colorScheme.primaryContainer
                  : null,
              foregroundColor: listenFirst
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.iconTheme.color,
            ),
            onPressed: () => onToggleListenFirst(targetId),
          ),
        ),
      ),
    );
  }

  /// A plain menu row, for the entries that do something rather than hold a
  /// state. The label takes the remaining width — these are the longest
  /// strings in the menu, and several locales run longer than English.
  PopupMenuItem<SpanCardAction> _actionItem({
    required SpanCardAction value,
    required IconData icon,
    required String label,
  }) => PopupMenuItem<SpanCardAction>(
    value: value,
    child: Row(
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    ),
  );

  /// A checked menu row, for the entries that are modes rather than trips.
  PopupMenuItem<SpanCardAction> _toggleItem({
    required SpanCardAction value,
    required IconData icon,
    required String label,
    required bool checked,
  }) => PopupMenuItem<SpanCardAction>(
    value: value,
    child: Semantics(
      checked: checked,
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          if (checked) const Icon(Icons.check, size: 18.0),
        ],
      ),
    ),
  );

  Widget _overflowMenu(
    BuildContext context, {
    required bool inMenuListenFirst,
  }) {
    final l10n = L10n.of(context);
    // Only one of the two controls ever holds the anchor, so the cached
    // GlobalKey is never claimed twice.
    final link = inMenuListenFirst
        ? MatrixState.pAnyState.layerLinkAndKey(targetId)
        : null;

    final menu = PopupMenuButton<SpanCardAction>(
      useRootNavigator: true,
      // An unnamed PopupMenuButton falls back to the framework default, and
      // the a11y floor check does not cover it. The tooltip is suppressed
      // inside this card (see SpanCard.build), so the icon carries the name.
      tooltip: l10n.moreOptions,
      icon: Icon(Icons.more_vert, semanticLabel: l10n.moreOptions),
      onSelected: (action) {
        switch (action) {
          case SpanCardAction.listenFirst:
            onToggleListenFirst(targetId);
          case SpanCardAction.autoIGC:
            onToggleAutoIGC();
          case SpanCardAction.feedback:
            onFeedback();
          case SpanCardAction.learningSettings:
            onLearningSettings();
        }
      },
      itemBuilder: (context) => [
        if (inMenuListenFirst && showListenFirst)
          _toggleItem(
            value: SpanCardAction.listenFirst,
            icon: listenFirst ? Icons.headphones : Icons.headphones_outlined,
            label: l10n.listenFirst,
            checked: listenFirst,
          ),
        _toggleItem(
          value: SpanCardAction.autoIGC,
          icon: Icons.auto_fix_high_outlined,
          label: l10n.autoIGCToolName,
          checked: autoIGC,
        ),
        _actionItem(
          value: SpanCardAction.feedback,
          icon: Icons.flag_outlined,
          label: l10n.reportContentIssue,
        ),
        _actionItem(
          value: SpanCardAction.learningSettings,
          icon: Icons.settings_outlined,
          label: l10n.learningSettings,
        ),
      ],
    );

    if (link == null) return menu;
    return CompositedTransformTarget(
      link: link.link,
      child: KeyedSubtree(key: link.key, child: menu),
    );
  }
}
