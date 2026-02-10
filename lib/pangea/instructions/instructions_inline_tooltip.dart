import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';

class InstructionsInlineTooltip extends StatelessWidget {
  final InstructionsEnum instructionsEnum;
  final bool animate;
  final EdgeInsets? padding;
  final TextStyle? textStyle;
  final List<InlineSpan>? richText;

  const InstructionsInlineTooltip({
    super.key,
    required this.instructionsEnum,
    this.animate = true,
    this.padding,
    this.textStyle,
    this.richText,
  });

  @override
  Widget build(BuildContext context) {
    return InlineTooltip(
      message: instructionsEnum.body(L10n.of(context)),
      isClosed: instructionsEnum.isToggledOff,
      onClose: () => instructionsEnum.setToggledOff(true),
      animate: animate,
      padding: padding,
      textStyle: textStyle,
      richText: richText,
    );
  }
}

class InlineTooltip extends StatefulWidget {
  final String message;
  final List<InlineSpan>? richText;
  final bool isClosed;

  final EdgeInsets? padding;
  final VoidCallback? onClose;
  final bool animate;

  final TextStyle? textStyle;

  const InlineTooltip({
    super.key,
    required this.message,
    required this.isClosed,
    this.richText,
    this.onClose,
    this.animate = true,
    this.padding,
    this.textStyle,
  });

  @override
  InlineTooltipState createState() => InlineTooltipState();
}

class InlineTooltipState extends State<InlineTooltip>
    with TickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _animation;

  bool _isClosed = true;

  @override
  void initState() {
    super.initState();
    _isClosed = widget.isClosed;
    _openTooltip();
  }

  @override
  void didUpdateWidget(covariant InlineTooltip oldWidget) {
    if (oldWidget.message != widget.message) {
      _isClosed = widget.isClosed;
      _openTooltip();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openTooltip() async {
    if (widget.animate) {
      _controller?.dispose();
      _controller = AnimationController(
        duration: FluffyThemes.animationDuration,
        vsync: this,
      );

      _animation = CurvedAnimation(
        parent: _controller!,
        curve: Curves.easeInOut,
      );

      // Start in correct state
      if (!_isClosed) {
        await _controller!.forward();
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> _closeTooltip() async {
    widget.onClose?.call();
    setState(() => _isClosed = true);

    if (widget.animate) {
      await _controller?.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: widget.padding ?? const EdgeInsets.all(0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          color: Color.alphaBlend(
            Theme.of(context).colorScheme.surface.withAlpha(70),
            AppConfig.gold,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: Icon(
                  Icons.lightbulb,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Flexible(
                child: Center(
                  child: widget.richText != null
                      ? RichText(
                          text: TextSpan(
                            children: widget.richText,
                            style:
                                widget.textStyle ??
                                (FluffyThemes.isColumnMode(context)
                                    ? Theme.of(context).textTheme.titleSmall
                                    : Theme.of(context).textTheme.bodyMedium),
                          ),
                          textAlign: TextAlign.center,
                        )
                      : Text(
                          widget.message,
                          style:
                              widget.textStyle ??
                              (FluffyThemes.isColumnMode(context)
                                  ? Theme.of(context).textTheme.titleSmall
                                  : Theme.of(context).textTheme.bodyMedium),
                          textAlign: TextAlign.center,
                        ),
                ),
              ),
              IconButton(
                padding: const EdgeInsets.only(left: 6.0),
                constraints: const BoxConstraints(),
                icon: Icon(
                  Icons.close_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onPressed: _closeTooltip,
              ),
            ],
          ),
        ),
      ),
    );

    return widget.animate
        ? SizeTransition(
            sizeFactor: _animation!,
            axisAlignment: -1.0,
            child: content,
          )
        : (_isClosed ? const SizedBox.shrink() : content);
  }
}
