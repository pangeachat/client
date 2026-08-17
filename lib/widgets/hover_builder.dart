import 'package:flutter/material.dart';

class HoverBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;

  /// Cursor for the hover region, so callers don't need a second
  /// [MouseRegion] wrapper just to set one (issue #8426).
  final MouseCursor cursor;

  const HoverBuilder({
    required this.builder,
    this.cursor = MouseCursor.defer,
    super.key,
  });

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => hovered
          ? null
          : setState(() {
              hovered = true;
            }),
      onExit: (_) => !hovered
          ? null
          : setState(() {
              hovered = false;
            }),
      child: widget.builder(context, hovered),
    );
  }
}
