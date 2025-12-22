import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/analytics_misc/lemma_emoji_setter_mixin.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/select_mode_buttons.dart';
import 'package:fluffychat/widgets/matrix.dart';

class TokenEmojiButton extends StatefulWidget {
  final ValueNotifier<SelectMode?> selectModeNotifier;
  final ValueNotifier<(ConstructIdentifier, String)?> constructEmojiNotifier;
  final VoidCallback onTap;

  final PangeaToken? token;
  final String? targetId;
  final bool enabled;
  final Color textColor;

  const TokenEmojiButton({
    super.key,
    required this.selectModeNotifier,
    required this.constructEmojiNotifier,
    required this.onTap,
    required this.textColor,
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
    widget.constructEmojiNotifier.addListener(_onUpdateEmoji);
  }

  @override
  void dispose() {
    _controller?.dispose();
    widget.selectModeNotifier.removeListener(_onUpdateSelectMode);
    widget.constructEmojiNotifier.removeListener(_onUpdateEmoji);
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

  void _onUpdateEmoji() {
    final value = widget.constructEmojiNotifier.value;
    if (value == null) return;

    final constructId = value.$1;
    final emoji = value.$2;

    if (mounted && constructId == widget.token?.vocabConstructID) {
      setState(() => _emoji = emoji);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sizeAnimation == null) {
      return const SizedBox.shrink();
    }

    final child = widget.enabled
        ? Text(
            _emoji ?? "-",
            style: TextStyle(fontSize: buttonSize - 8.0).copyWith(
              color: widget.textColor,
            ),
            textScaler: TextScaler.noScaling,
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
                    onTap: widget.onTap,
                    borderRadius: BorderRadius.circular(99.0),
                    child: Container(
                      height: _sizeAnimation!.value,
                      width: widget.enabled ? _sizeAnimation!.value : 0,
                      alignment: Alignment.center,
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
