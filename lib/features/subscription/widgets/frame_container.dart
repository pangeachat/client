import 'package:flutter/material.dart';

class FrameContainer extends StatefulWidget {
  final Widget child;
  final String title;

  final Color frameColor;
  final Color backgroundColor;
  final Color foregroundColor;

  final double borderWidth;
  final double borderRadius;

  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry titlePadding;

  final bool expandable;
  final bool initiallyExpanded;

  const FrameContainer({
    super.key,
    required this.title,
    required this.child,
    required this.frameColor,
    required this.backgroundColor,
    required this.foregroundColor,
    this.borderWidth = 3,
    this.borderRadius = 24,
    this.padding = const EdgeInsets.all(24),
    this.titlePadding = const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 12,
    ),
    this.expandable = false,
    this.initiallyExpanded = true,
  });

  @override
  State<FrameContainer> createState() => _FrameContainerState();
}

class _FrameContainerState extends State<FrameContainer>
    with SingleTickerProviderStateMixin {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.frameColor,
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      padding: EdgeInsets.all(widget.borderWidth),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          widget.borderRadius - widget.borderWidth,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              color: widget.frameColor,
              padding: widget.titlePadding,
              child: Row(
                children: [
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(
                        widget.title,
                        textAlign: widget.expandable
                            ? TextAlign.start
                            : TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: widget.foregroundColor,
                        ),
                      ),
                    ),
                  ),
                  if (widget.expandable)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      splashRadius: 20,
                      color: widget.foregroundColor,
                      icon: AnimatedRotation(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        turns: _expanded ? 0.5 : 0.0,
                        child: const Icon(Icons.expand_less),
                      ),
                      onPressed: () {
                        setState(() {
                          _expanded = !_expanded;
                        });
                      },
                    ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: ClipRect(
                child: _expanded
                    ? Container(
                        width: double.infinity,
                        alignment: Alignment.center,
                        padding: widget.padding,
                        decoration: BoxDecoration(
                          color: widget.backgroundColor,
                        ),
                        child: widget.child,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
