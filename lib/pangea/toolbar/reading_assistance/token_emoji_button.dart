import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/analytics_misc/lemma_emoji_setter_mixin.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma_meaning_builder.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/lemma_emoji_picker.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/select_mode_buttons.dart';
import 'package:fluffychat/widgets/matrix.dart';

class TokenEmojiButton extends StatefulWidget {
  final ValueNotifier<SelectMode?> selectModeNotifier;
  final ValueNotifier<PangeaToken?> selectedTokenNotifier;

  final PangeaToken? token;
  final String? targetId;
  final bool enabled;

  const TokenEmojiButton({
    super.key,
    required this.selectModeNotifier,
    required this.selectedTokenNotifier,
    this.token,
    this.targetId,
    this.enabled = true,
  });

  @override
  State<TokenEmojiButton> createState() => TokenEmojiButtonState();
}

class TokenEmojiButtonState extends State<TokenEmojiButton>
    with TickerProviderStateMixin, LemmaEmojiSetter {
  final double buttonSize = 24.0;
  SelectMode? _prevMode;
  AnimationController? _controller;
  Animation<double>? _sizeAnimation;

  String? _emoji;

  @override
  void initState() {
    super.initState();
    _emoji = widget.token?.vocabConstructID.userSetEmoji.firstOrNull;

    _initAnimation();
    _prevMode = widget.selectModeNotifier.value;
    widget.selectModeNotifier.addListener(_onUpdateSelectMode);
    widget.selectedTokenNotifier.addListener(_onSelectToken);
  }

  @override
  void dispose() {
    _controller?.dispose();
    widget.selectModeNotifier.removeListener(_onUpdateSelectMode);
    widget.selectedTokenNotifier.removeListener(_onSelectToken);
    super.dispose();
  }

  void _initAnimation() {
    if (MatrixState.pangeaController.subscriptionController.isSubscribed ==
        false) {
      return;
    }

    _controller = AnimationController(
      vsync: this,
      duration: FluffyThemes.animationDuration,
    );

    _sizeAnimation = Tween<double>(
      begin: 0,
      end: buttonSize,
    ).animate(CurvedAnimation(parent: _controller!, curve: Curves.easeOut));
  }

  void _onUpdateSelectMode() {
    final mode = widget.selectModeNotifier.value;
    if (_prevMode != SelectMode.emoji && mode == SelectMode.emoji) {
      _controller?.forward();
    } else if (_prevMode == SelectMode.emoji && mode != SelectMode.emoji) {
      _controller?.reverse();
    }
    _prevMode = mode;
  }

  void _onSelectToken() {
    final selected = widget.selectedTokenNotifier.value;
    if (selected != null && selected == widget.token) {
      showTokenEmojiPopup();
    }
  }

  void showTokenEmojiPopup() {
    if (widget.targetId == null || widget.token == null) return;
    OverlayUtil.showPositionedCard(
      overlayKey: "overlay_emoji_selector",
      context: context,
      cardToShow: LemmaMeaningBuilder(
        langCode: MatrixState.pangeaController.userController.userL2Code!,
        constructId: widget.token!.vocabConstructID,
        builder: (context, controller) {
          return Material(
            type: MaterialType.transparency,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(
                  AppConfig.borderRadius,
                ),
              ),
              child: LemmaEmojiPicker(
                emojis: controller.lemmaInfo?.emoji ?? [],
                onSelect: (emoji) {
                  _setTokenEmoji(emoji);
                  MatrixState.pAnyState.closeOverlay("overlay_emoji_selector");
                },
                loading: controller.isLoading,
              ),
            ),
          );
        },
      ),
      transformTargetId: widget.targetId!,
      closePrevOverlay: false,
      addBorder: false,
      maxWidth: (40 * 5) + (4 * 5) + 16,
      maxHeight: 60,
    );
  }

  void _setTokenEmoji(String emoji) {
    setState(() => _emoji = emoji);

    if (widget.targetId == null || widget.token == null) return;
    setLemmaEmoji(
      widget.token!.vocabConstructID,
      emoji,
      widget.targetId,
    ).catchError((e, s) {
      ErrorHandler.logError(
        data: widget.token!.toJson(),
        e: e,
        s: s,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_sizeAnimation == null) {
      return const SizedBox.shrink();
    }

    final child = widget.enabled
        ? _emoji != null
            ? Text(
                _emoji!,
                style: TextStyle(fontSize: buttonSize - 8.0),
                textScaler: TextScaler.noScaling,
              )
            : Icon(
                Icons.add_reaction_outlined,
                size: buttonSize - 8.0,
                color: Theme.of(context).colorScheme.primary,
              )
        : null;

    final content = ValueListenableBuilder(
      valueListenable: widget.selectModeNotifier,
      builder: (context, mode, __) {
        return mode == SelectMode.emoji
            ? AnimatedBuilder(
                key: widget.targetId != null
                    ? MatrixState.pAnyState
                        .layerLinkAndKey(widget.targetId!)
                        .key
                    : null,
                animation: _sizeAnimation!,
                child: child,
                builder: (context, child) {
                  return InkWell(
                    onTap: showTokenEmojiPopup,
                    borderRadius: BorderRadius.circular(99.0),
                    child: Container(
                      height: _sizeAnimation!.value,
                      width: widget.enabled ? _sizeAnimation!.value : 0,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          border: Border.all(color: Colors.green)),
                      child: child,
                    ),
                  );
                },
              )
            : const SizedBox();
      },
    );

    return widget.targetId != null
        ? CompositedTransformTarget(
            link: MatrixState.pAnyState.layerLinkAndKey(widget.targetId!).link,
            child: content,
          )
        : content;
  }
}
