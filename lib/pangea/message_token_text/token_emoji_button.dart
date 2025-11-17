import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/toolbar/widgets/select_mode_buttons.dart';
import 'package:fluffychat/widgets/matrix.dart';

class TokenEmojiButton extends StatefulWidget {
  final ValueNotifier<SelectMode?> selectModeNotifier;
  final bool enabled;
  final String? emoji;
  final String? targetId;
  final VoidCallback? onSelect;

  const TokenEmojiButton({
    super.key,
    required this.selectModeNotifier,
    this.enabled = true,
    this.emoji,
    this.targetId,
    this.onSelect,
  });

  @override
  State<TokenEmojiButton> createState() => TokenEmojiButtonState();
}

class TokenEmojiButtonState extends State<TokenEmojiButton>
    with TickerProviderStateMixin {
  final double buttonSize = 20.0;
  SelectMode? _prevMode;
  AnimationController? _controller;
  Animation<double>? _sizeAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimation();
    _prevMode = widget.selectModeNotifier.value;
    widget.selectModeNotifier.addListener(_onUpdateSelectMode);
  }

  @override
  void dispose() {
    _controller?.dispose();
    widget.selectModeNotifier.removeListener(_onUpdateSelectMode);
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

  @override
  Widget build(BuildContext context) {
    if (_sizeAnimation == null) {
      return const SizedBox.shrink();
    }

    final child = widget.enabled
        ? InkWell(
            onTap: widget.onSelect,
            borderRadius: BorderRadius.circular(99.0),
            child: widget.emoji != null
                ? Text(
                    widget.emoji!,
                    style: TextStyle(fontSize: buttonSize - 4.0),
                    textScaler: TextScaler.noScaling,
                  )
                : Icon(
                    Icons.add_reaction_outlined,
                    size: buttonSize - 4.0,
                    color: Theme.of(context).colorScheme.primary,
                  ),
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
                  return Container(
                    height: _sizeAnimation!.value,
                    width: widget.enabled ? _sizeAnimation!.value : 0,
                    alignment: Alignment.center,
                    child: child,
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
