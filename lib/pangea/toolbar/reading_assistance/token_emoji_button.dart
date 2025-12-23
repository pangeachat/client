import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/analytics_misc/lemma_emoji_setter_mixin.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/select_mode_buttons.dart';
import 'package:fluffychat/widgets/matrix.dart';

class TokenEmojiButton extends StatelessWidget with LemmaEmojiSetter {
  static const double _buttonSize = 24.0;

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

  bool get _canShow =>
      MatrixState.pangeaController.subscriptionController.isSubscribed != false;

  @override
  Widget build(BuildContext context) {
    if (!_canShow) return const SizedBox.shrink();

    Widget content = ValueListenableBuilder<SelectMode?>(
      valueListenable: selectModeNotifier,
      builder: (context, mode, _) {
        final visible = mode == SelectMode.emoji;

        return AnimatedSize(
          duration: FluffyThemes.animationDuration,
          curve: Curves.easeOut,
          alignment: Alignment.center,
          child: visible
              ? InkWell(
                  onTap: enabled ? onTap : null,
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                    width: _buttonSize,
                    height: _buttonSize,
                    child: Center(
                      child: _EmojiText(
                        token: token,
                        enabled: enabled,
                        textColor: textColor,
                        fontSize: _buttonSize - 8,
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
        child: KeyedSubtree(
          key: layer.key,
          child: content,
        ),
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
      stream: Matrix.of(context)
          .analyticsDataService
          .updateDispatcher
          .lemmaUpdateStream(token!.vocabConstructID),
      builder: (context, snapshot) {
        final emoji = snapshot.data?.emojis?.firstOrNull ??
            token!.vocabConstructID.userSetEmoji;

        return Text(
          emoji ?? "-",
          style: TextStyle(
            fontSize: fontSize,
            color: textColor,
          ),
          textScaler: TextScaler.noScaling,
        );
      },
    );
  }
}
