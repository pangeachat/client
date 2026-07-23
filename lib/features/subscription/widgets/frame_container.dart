import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

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

  final TextStyle? titleStyle;

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
    this.titleStyle,
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

  void _toggleExpanded() => setState(() => _expanded = !_expanded);

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
            Semantics(
              header: true,
              button: widget.expandable,
              toggled: widget.expandable ? _expanded : null,
              label: widget.title,
              onTap: widget.expandable ? _toggleExpanded : null,
              excludeSemantics:
                  true, // suppress children's own semantics; we've already described the whole node
              child: InkWell(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(widget.borderRadius),
                  topRight: Radius.circular(widget.borderRadius),
                ),
                onTap: widget.expandable ? _toggleExpanded : null,
                child: Container(
                  width: double.infinity,
                  color: widget.frameColor,
                  padding: widget.titlePadding,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          textAlign: widget.expandable
                              ? TextAlign.start
                              : TextAlign.center,
                          style:
                              widget.titleStyle ??
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: widget.foregroundColor,
                              ),
                        ),
                      ),
                      if (widget.expandable)
                        IconButton(
                          tooltip: _expanded
                              ? L10n.of(context).close
                              : L10n.of(context).open,
                          visualDensity: VisualDensity.compact,
                          splashRadius: 20,
                          color: widget.foregroundColor,
                          icon: AnimatedRotation(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            turns: _expanded ? 0.5 : 0.0,
                            child: const Icon(Icons.expand_less),
                          ),
                          onPressed: _toggleExpanded,
                        ),
                    ],
                  ),
                ),
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
