import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/pangea/tokens/tokens_util.dart';
import 'package:fluffychat/widgets/matrix.dart';

class NewWordOverlay extends StatefulWidget {
  final String overlayKey;
  const NewWordOverlay({super.key, required this.overlayKey});

  static void show({
    required BuildContext context,
    required String target,
    required String overlayKey,
  }) {
    OverlayUtil.showOverlay(
      context: context,
      closePrevOverlay: false,
      ignorePointer: true,
      canPop: false,
      offset: const Offset(0, 45),
      targetAnchor: Alignment.center,
      overlayKey: overlayKey,
      transformTargetId: target,
      child: NewWordOverlay(overlayKey: overlayKey),
    );
  }

  @override
  NewWordOverlayState createState() => NewWordOverlayState();
}

class NewWordOverlayState extends State<NewWordOverlay>
    with TickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _opacityAnim;
  Animation<double>? _moveAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TokensUtil.instance.clearRecentlyCollected();
    });

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _opacityAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 25,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 25),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
    ]).animate(_controller!);

    _moveAnim = CurvedAnimation(
      parent: _controller!,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
    );

    _controller?.forward().then((_) {
      if (!mounted) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        MatrixState.pAnyState.closeOverlay(widget.overlayKey);
      });
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller!,
      builder: (context, child) {
        final opacity = _opacityAnim!.value;
        final move = _moveAnim!.value;
        final moveY = -move * 60;

        return Transform.translate(
          offset: Offset(0, moveY),
          child: Opacity(
            opacity: opacity,
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.all(Radius.circular(16.0)),
              ),
              padding: const EdgeInsets.symmetric(
                vertical: 8.0,
                horizontal: 16.0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Symbols.dictionary,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 4.0),
                  Text(
                    "+ 1",
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
