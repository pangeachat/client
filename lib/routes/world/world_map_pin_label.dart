import 'package:flutter/material.dart';

import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// A Google-Maps-style activity-name label for a mid map pin: [title] in the
/// pin's state [color] with a thin white halo so it stays legible over the map
/// (world-map.instructions.md, "Pin display"). The side beside the pin is
/// chosen by the [placePinLabels] geometry pass; this widget is pure
/// presentation. It's sized by its enclosing marker box (measured to match
/// [kPinLabelTextStyle]), so the text already fits — [kPinLabelMaxWidth] caps
/// it upstream and it ellipsizes if ever over. Non-interactive: the caller
/// wraps it in an [IgnorePointer] so the wide box never intercepts pin/map taps.
class WorldMapPinLabel extends StatelessWidget {
  final String title;
  final Color color;

  /// 0..1 — dims an understaffed `available` pin's label to match its pin
  /// (world-map.instructions.md, "Understaffed pins"). 1.0 = fully opaque.
  final double opacity;

  const WorldMapPinLabel({
    required this.title,
    required this.color,
    this.opacity = 1.0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    Widget text(TextStyle style) =>
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    // Theme-dependent halo (stroked) painted behind the coloured fill: the
    // surface colour reads light in light mode and dark in dark mode, so the
    // outline stays legible over the map tiles in either theme (reuses the
    // same colorScheme.surface the star dot / large card already halo against
    // — world_map_state_dot.dart, world_map_large_card.dart).
    final haloColor = Theme.of(context).colorScheme.surface;
    final label = Stack(
      alignment: Alignment.center,
      children: [
        text(
          kPinLabelTextStyle.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeJoin = StrokeJoin.round
              ..color = haloColor,
          ),
        ),
        text(kPinLabelTextStyle.copyWith(color: color)),
      ],
    );
    return opacity >= 1.0 ? label : Opacity(opacity: opacity, child: label);
  }
}
