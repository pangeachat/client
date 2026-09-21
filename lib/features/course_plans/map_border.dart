import 'package:flutter/material.dart';

import 'package:fluffychat/features/course_plans/map_clipper.dart';

/// [MapClipper]'s folded-map banner outline as an [OutlinedBorder], so a
/// focus ring can trace the course avatar's actual silhouette — a circular
/// ring floats over the notched banner and reads as stray arcs (#8724).
class MapBorder extends OutlinedBorder {
  const MapBorder({super.side});

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      MapClipper.pathFor(rect.size).shift(rect.topLeft);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(getOuterPath(rect), side.toPaint());
  }

  @override
  MapBorder copyWith({BorderSide? side}) => MapBorder(side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => MapBorder(side: side.scale(t));
}
