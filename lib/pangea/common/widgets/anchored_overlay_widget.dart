import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/common/utils/cutout_painter.dart';
import 'package:fluffychat/widgets/matrix.dart';

class AnchoredOverlayWidget extends StatefulWidget {
  final Rect anchorRect;
  final String overlayKey;

  final Widget? overlayContent;
  final double borderRadius;
  final double padding;
  final VoidCallback? onClick;

  const AnchoredOverlayWidget({
    required this.anchorRect,
    required this.overlayKey,
    this.overlayContent,
    this.borderRadius = 0.0,
    this.padding = 6.0,
    this.onClick,
    super.key,
  });

  @override
  State<AnchoredOverlayWidget> createState() => _AnchoredOverlayWidgetState();
}

class _AnchoredOverlayWidgetState extends State<AnchoredOverlayWidget> {
  final ValueNotifier<bool> _visible = ValueNotifier<bool>(false);

  static const double overlayWidth = 300.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _visible.value = true);
  }

  @override
  void dispose() {
    _visible.dispose();
    super.dispose();
  }

  Future<void> _onTap(TapDownDetails details) async {
    final tapPos = details.globalPosition;
    if (!widget.anchorRect.contains(tapPos)) return;

    if (mounted) {
      _visible.value = false;
      await Future.delayed(FluffyThemes.animationDuration);
    }

    MatrixState.pAnyState.closeOverlay(widget.overlayKey);
    widget.onClick?.call();
  }

  @override
  Widget build(BuildContext context) {
    final leftPosition =
        (widget.anchorRect.left +
                (widget.anchorRect.width / 2) -
                (overlayWidth / 2))
            .clamp(8.0, MediaQuery.sizeOf(context).width - overlayWidth - 8.0);

    return ValueListenableBuilder<bool>(
      valueListenable: _visible,
      builder: (context, visible, child) {
        return AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: FluffyThemes.animationDuration,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: _onTap,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: CutoutBackgroundPainter(
                        holeRect: widget.anchorRect,
                        backgroundColor: Colors.black.withAlpha(180),
                        borderRadius: widget.borderRadius,
                        padding: widget.padding,
                      ),
                    ),
                  ),
                  Positioned(
                    left: leftPosition,
                    top: widget.anchorRect.bottom + widget.padding,
                    child: Material(
                      color: Colors.transparent,
                      elevation: 4,
                      child: SizedBox(
                        width: overlayWidth,
                        child: widget.overlayContent,
                      ),
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
