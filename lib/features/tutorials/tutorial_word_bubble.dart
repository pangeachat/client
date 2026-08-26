import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/features/tutorials/tutorial_copy.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/events/tokens/collectable_tokens_mixin.dart';
import 'package:fluffychat/routes/chat/events/tokens/token_rendering_util.dart';
import 'package:fluffychat/routes/chat/events/tokens/tokens_util.dart';
import 'package:fluffychat/routes/chat/events/tokens/underline_text_widget.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/word_zoom_widget.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The welcome tutorial's L2 greeting, rendered as a **vocabulary word** rather
/// than as text: a bubble the learner can tap to open its word card, which also
/// collects the word.
///
/// It is the learner's first contact with the mechanic the product runs on —
/// words in the L2 are things you can touch, look up and collect — so it borrows
/// the chat's own styling rather than inventing a tutorial-only look. See
/// tutorials.instructions.md.
class TutorialWordBubble extends StatefulWidget {
  final TutorialGreeting greeting;

  /// Style of the copy this bubble sits inside, so the word matches the
  /// sentence it interrupts.
  final TextStyle? style;

  const TutorialWordBubble({required this.greeting, this.style, super.key});

  @override
  State<TutorialWordBubble> createState() => _TutorialWordBubbleState();
}

class _TutorialWordBubbleState extends State<TutorialWordBubble>
    with CollectableTokensMixin {
  static const String _targetId = 'tutorial_welcome_greeting';
  static const String _cacheKey = 'tutorial_welcome_greeting';

  bool _isNew = false;
  bool _cardOpen = false;
  StreamSubscription? _analyticsSubscription;

  @override
  void initState() {
    super.initState();
    // The profile and the analytics room both land asynchronously, and until
    // they do the service reports every construct as already known. So this is
    // re-asked rather than concluded — the same rule every tutorial trigger
    // follows. See tutorials.instructions.md.
    _analyticsSubscription = MatrixState
        .pangeaController
        .matrixState
        .analyticsDataService
        .updateDispatcher
        .constructUpdateStream
        .stream
        .listen((_) => _computeIsNew());
    _computeIsNew();
  }

  @override
  void dispose() {
    _analyticsSubscription?.cancel();
    MatrixState.pAnyState.closeOverlay(_targetId);
    super.dispose();
  }

  void _computeIsNew() {
    final token = widget.greeting.token;
    final langCode = widget.greeting.langCode;
    if (token == null || langCode == null) return;

    // A greeting is usually tagged as an interjection, which is a function word
    // — and only content words are ever reported new, so this is normally false
    // and the bubble simply carries no green underline. Asked anyway rather than
    // assumed: what the tokenizer returns varies by language, and deciding here
    // would put a second, quietly disagreeing answer next to the real one.
    final isNew = TokensUtil.instance
        .getNewTokens(_cacheKey, [token], langCode)
        .any((t) => t == token.text);

    if (mounted && isNew != _isNew) setState(() => _isNew = isNew);
  }

  Future<void> _onTap() async {
    final token = widget.greeting.token;
    final langCode = widget.greeting.langCode;
    if (token == null || langCode == null) return;

    // Collected on tap, so the greeting is also the learner's first collected
    // word — but only once. Already recorded means they have it already (a
    // learner who reset their tooltips, or a second look at this step), and
    // collecting again would award the same word twice.
    final analytics =
        MatrixState.pangeaController.matrixState.analyticsDataService;
    final collecting = analytics.hasUsedConstruct(token.vocabConstructID)
        ? null
        : collectToken(
            token: token,
            tokenCacheKey: _cacheKey,
            targetId: _targetId,
            langCode: langCode,
            // Not a chat token, so it must not retire the shimmer that teaches
            // the learner to tap words in their first real message.
            retireNewTokenShimmer: false,
          );

    // Started before the card, deliberately: collecting marks the word
    // just-collected synchronously, before its first await, and that is what the
    // card reads to decide whether to celebrate it. Not awaited — an analytics
    // round trip must not sit between the learner's tap and the card.
    _showWordCard(token.text, token.pos, langCode);

    await collecting;
    _computeIsNew();
  }

  /// Opens above the word where there is room, and flips below where there is
  /// not — [OverlayUtil.showPositionedCard] decides. Post-frame so the bubble it
  /// anchors to has been laid out.
  void _showWordCard(PangeaTokenText token, String pos, String langCode) {
    if (_cardOpen) return;
    setState(() => _cardOpen = true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      OverlayUtil.showPositionedCard(
        context: context,
        cardToShow: WordZoomWidget(
          token: token,
          construct: widget.greeting.token!.vocabConstructID,
          langCode: langCode,
          pos: pos,
          enableEmojiSelection: true,
          enableEmojiReactions: false,
          enableAnalyticsNavigation: false,
          onClose: () => _closeWordCard(),
        ),
        displayDetails: PositionedOverlayDisplayDetails(
          overlayKey: _targetId,
          transformTargetId: _targetId,
          closePrevOverlay: false,
          addBorder: false,
          maxWidth: AppConfig.toolbarMinWidth,
          maxHeight: AppConfig.scaledToolbarMaxHeight(context),
          // The tutorial scrim is a BLOCKING overlay, which the registry
          // otherwise refuses to open anything over — the same escape the chat
          // uses to open its toolbar mid-tutorial. Root overlay so the card
          // paints above the scrim rather than under it.
          bypassBlockingOverlays: true,
          rootOverlay: true,
          onDismiss: _closeWordCard,
        ),
      );
    });
  }

  void _closeWordCard() {
    MatrixState.pAnyState.closeOverlay(_targetId);
    if (mounted && _cardOpen) setState(() => _cardOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = MatrixState.pAnyState.layerLinkAndKey(_targetId);

    return CompositedTransformTarget(
      link: target.link,
      child: HoverBuilder(
        builder: (context, hovered) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            // Wins the gesture arena over the overlay's advance-on-tap, so
            // reading the word does not skip past the step.
            onTap: _onTap,
            child: Container(
              key: target.key,
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withAlpha(_cardOpen ? 40 : 20),
                borderRadius: BorderRadius.circular(20.0),
              ),
              child: UnderlineText(
                text: widget.greeting.word,
                style: widget.style ?? DefaultTextStyle.of(context).style,
                underlineColor: TokenRenderingUtil.underlineColor(
                  theme.colorScheme.primary.withAlpha(200),
                  isNew: _isNew,
                  selected: _cardOpen,
                  hovered: hovered,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
