import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/languages/language_constants.dart';
import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/repo/token_api_models.dart';
import 'package:fluffychat/routes/chat/events/repo/tokens_repo.dart';
import 'package:fluffychat/routes/chat/events/tokens/token_rendering_util.dart';
import 'package:fluffychat/routes/chat/events/tokens/tokens_util.dart';
import 'package:fluffychat/routes/chat/events/tokens/underline_text_widget.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/word_zoom_widget.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// One stretch of call-transcript text with its words made tappable, so tapping
/// a word opens its word card (#8797).
///
/// This reuses the mechanism the chat already uses for voice-message
/// transcripts and nothing here is new: [TokensRepo] is the same `/tokenize`
/// call, and the card is the same [WordZoomWidget] shown through the same
/// [OverlayUtil.showPositionedCard] the activity-vocab and style-example
/// surfaces use with no backing message event.
///
/// The transcript persists only text -- per-word tokens were deliberately not
/// stored (see `TranscriptSegment`) -- so tokens are derived at read time.
/// Word cards are an enhancement OVER the transcript, never a gate on reading
/// it: while tokens are pending, and on any tokenizer failure, empty result, or
/// a response that does not cleanly cover the text, the words show as plain
/// [SelectableText]. See [_TappableTokens] for that last, load-bearing case.
class TranscriptTokens extends StatefulWidget {
  final String text;

  /// The language this stretch was transcribed in, from the half's `lang_code`.
  /// Null when the writer never recorded one; the tokenizer then detects it and
  /// the card opens in the detected language.
  final String? langCode;

  final TextStyle? style;

  /// Injected by tests to fake the tokenizer network call. Production leaves it
  /// null and tokenizes through [TokensRepo].
  final Future<TokensResponseModel?> Function(String text, String? langCode)?
  tokenize;

  const TranscriptTokens({
    required this.text,
    this.langCode,
    this.style,
    this.tokenize,
    super.key,
  });

  @override
  State<TranscriptTokens> createState() => _TranscriptTokensState();
}

/// Hands each state instance a process-unique id, so two transcript stretches
/// that open with the same word at the same offset produce DIFFERENT overlay
/// keys rather than registering one `GlobalKey` twice (which crashes the frame).
int _instanceSeq = 0;

class _TranscriptTokensState extends State<TranscriptTokens> {
  late Future<TokensResponseModel?> _tokens;
  late final String _uid = '${_instanceSeq++}';

  @override
  void initState() {
    super.initState();
    _tokens = _load();
  }

  @override
  void didUpdateWidget(TranscriptTokens oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.langCode != widget.langCode) {
      _tokens = _load();
    }
  }

  Future<TokensResponseModel?> _load() =>
      (widget.tokenize ?? _tokenizeViaRepo)(widget.text, widget.langCode);

  Future<TokensResponseModel?> _tokenizeViaRepo(
    String text,
    String? langCode,
  ) async {
    // [langCode] selects the tokenizer model; the reader's own L1/L2 are what
    // gate save-vocab eligibility and the card's translation, exactly as a
    // voice message tokenizes against its reader.
    final user = MatrixState.pangeaController.userController;
    final result = await TokensRepo.instance.get(
      TokensRequestModel(
        fullText: text,
        langCode: langCode,
        senderL1: user.userL1?.langCode ?? LanguageKeys.unknownLanguage,
        senderL2:
            langCode ?? user.userL2?.langCode ?? LanguageKeys.unknownLanguage,
      ),
    );
    // A tokenizer failure costs the WORD CARDS, never the words.
    if (result.isError || result.asValue == null) return null;
    return result.asValue!.value;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    return FutureBuilder<TokensResponseModel?>(
      future: _tokens,
      builder: (context, snapshot) {
        final response = snapshot.data;
        // Plain, selectable text while loading and on any failure, so the
        // transcript is always readable even when the tokenizer is not reached.
        if (snapshot.connectionState != ConnectionState.done ||
            response == null ||
            response.tokens.isEmpty) {
          return SelectableText(widget.text, style: style);
        }
        return _TappableTokens(
          text: widget.text,
          tokens: response.tokens,
          // The half's own language when it had one, else what the tokenizer
          // detected -- so the card always opens in the language of the words.
          langCode: widget.langCode ?? response.lang,
          style: style,
          uid: _uid,
        );
      },
    );
  }
}

class _TappableTokens extends StatelessWidget {
  final String text;
  final List<PangeaToken> tokens;
  final String langCode;
  final TextStyle style;
  final String uid;

  const _TappableTokens({
    required this.text,
    required this.tokens,
    required this.langCode,
    required this.style,
    required this.uid,
  });

  void _openCard(BuildContext context, PangeaToken token, String target) {
    OverlayUtil.showPositionedCard(
      context: context,
      cardToShow: WordZoomWidget(
        token: token.text,
        construct: token.vocabConstructID,
        langCode: langCode,
        pos: token.pos,
        morph: token.morph.map((key, value) => MapEntry(key.name, value)),
        // A transcript is not a room message. `event` backs only the two
        // affordances that need one -- the report-feedback flag and emoji
        // reactions on the message -- so both stay off. Emoji selection and
        // analytics navigation need no event and stay ON, so this is the app's
        // ordinary word card, not a stripped variant (the exact standalone
        // configuration the activity-vocab card uses).
        event: null,
        enableEmojiSelection: true,
        enableEmojiReactions: false,
        enableAnalyticsNavigation: true,
        onClose: () => MatrixState.pAnyState.closeOverlay(target),
      ),
      displayDetails: PositionedOverlayDisplayDetails(
        overlayKey: target,
        transformTargetId: target,
        // WordZoomWidget draws its OWN card border; the default `addBorder: true`
        // wraps it in a second bordered OverlayContainer whose constraints also
        // clip the card. Off, exactly as the activity-vocab card sets it -- the
        // single-border, uncramped card the rest of the app shows (#8797).
        addBorder: false,
        maxWidth: AppConfig.toolbarMinWidth,
        maxHeight: AppConfig.scaledToolbarMaxHeight(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final characters = text.characters;
    final positions = TokensUtil.instance.getGlobalTokenPositions(
      tokens,
      transcript: text,
    );
    final slices = [
      for (final position in positions)
        characters
            .skip(position.startIndex)
            .take(position.endIndex - position.startIndex)
            .toString(),
    ];

    // Fail CLOSED to plain text unless the token spans reconstruct the WHOLE
    // transcript, character for character. A partial tokenizer response (a
    // trailing word missing) would otherwise drop visible text, and a malformed
    // one (two tokens on the same span) would both overlap the slices AND
    // register one overlay key twice, crashing the frame. Either way the rule
    // holds: a transcript is always readable, so a tokenization that does not
    // cleanly cover it falls back to the plain words.
    if (slices.join() != text) {
      return SelectableText(text, style: style);
    }

    return RichText(
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(
        style: style,
        children: [
          for (final (index, position) in positions.indexed)
            if (position.token == null)
              TextSpan(text: slices[index], style: style)
            else
              _tokenSpan(context, position.token!, slices[index], index),
        ],
      ),
    );
  }

  InlineSpan _tokenSpan(
    BuildContext context,
    PangeaToken token,
    String slice,
    int index,
  ) {
    // Unique per span AND per widget instance: `index` separates two words in
    // one stretch, `uid` separates two stretches, so no two rendered words ever
    // share the overlay's GlobalKey.
    final target = 'call-transcript-token-$uid-$index';
    final linkAndKey = MatrixState.pAnyState.layerLinkAndKey(target);
    return WidgetSpan(
      // A WidgetSpan child is already scaled by its placeholder; scaling its
      // text again squares the device text size (#7719).
      child: MediaQuery.withNoTextScaling(
        child: CompositedTransformTarget(
          link: linkAndKey.link,
          child: HoverBuilder(
            builder: (context, hovered) => MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: linkAndKey.key,
                behavior: HitTestBehavior.translucent,
                onTap: () => _openCard(context, token, target),
                child: UnderlineText(
                  text: slice,
                  style: style,
                  underlineColor: TokenRenderingUtil.underlineColor(
                    Theme.of(context).colorScheme.primary.withAlpha(200),
                    selected: false,
                    hovered: hovered,
                    isNew: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
