import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/toolbar/reading_assistance/select_mode_buttons.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/lemma_emoji_setter_mixin.dart';
import 'package:fluffychat/utils/text_scaler_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

class TokenEmojiButton extends StatelessWidget with LemmaEmojiSetter {
  static const double _buttonSize = 24.0;
  static const double _glyphSize = _buttonSize - 8;

  final ValueNotifier<SelectMode?> selectModeNotifier;
  final VoidCallback onTap;
  final PangeaToken? token;
  final String? targetId;
  final bool enabled;
  final Color textColor;

  const TokenEmojiButton({
    super.key,
    required this.selectModeNotifier,
    required this.onTap,
    required this.textColor,
    this.token,
    this.targetId,
    this.enabled = true,
  });

  bool get _canShow => MatrixState
      .pangeaController
      .subscriptionController
      .showSubscriptionGatedContent;

  @override
  Widget build(BuildContext context) {
    if (!_canShow) return const SizedBox.shrink();

    Widget content = ValueListenableBuilder<SelectMode?>(
      valueListenable: selectModeNotifier,
      builder: (context, mode, _) {
        final visible = mode == SelectMode.emoji;

        // The glyph scales with the device text size, so the button box grows
        // by the factor the scaler applies at the glyph's own font size — not
        // by `scale(_buttonSize)`, which asks a non-linear scaler what a 24pt
        // *font* would become (accessibility.instructions.md, Text scaling).
        final glyphScale = MediaQuery.textScalerOf(
          context,
        ).factorAt(_glyphSize);

        return AnimatedSize(
          duration: FluffyThemes.animationDuration,
          curve: Curves.easeOut,
          alignment: Alignment.center,
          child: visible
              ? InkWell(
                  onTap: enabled ? onTap : null,
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                    width: _buttonSize * glyphScale,
                    height: _buttonSize * glyphScale,
                    child: Center(
                      child: _EmojiText(
                        token: token,
                        enabled: enabled,
                        textColor: textColor,
                        fontSize: _glyphSize,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        );
      },
    );

    if (targetId != null) {
      final layer = MatrixState.pAnyState.layerLinkAndKey(targetId!);
      content = CompositedTransformTarget(
        link: layer.link,
        child: KeyedSubtree(key: layer.key, child: content),
      );
    }

    return content;
  }
}

class _EmojiText extends StatelessWidget {
  final PangeaToken? token;
  final bool enabled;
  final Color textColor;
  final double fontSize;

  const _EmojiText({
    required this.token,
    required this.enabled,
    required this.textColor,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled || token == null) return const SizedBox.shrink();

    return StreamBuilder(
      stream: Matrix.of(context).analyticsDataService.updateDispatcher
          .lemmaUpdateStream(token!.vocabConstructID),
      builder: (context, snapshot) {
        final emoji =
            snapshot.data?.emojis?.firstOrNull ??
            token!.vocabConstructID.userSetEmoji;

        return Text(
          emoji ?? "-",
          style: TextStyle(fontSize: fontSize, color: textColor),
        );
      },
    );
  }
}
