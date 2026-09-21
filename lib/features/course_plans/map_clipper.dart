import 'package:flutter/material.dart';

class MapClipper extends CustomClipper<Path> {
  /// The folded-map banner outline, shared with MapBorder (map_border.dart)
  /// so the course avatar's focus ring traces exactly the silhouette this
  /// clips (#8724).
  ///
  /// The path starts at the top-left notch point (0, 0.15h) — NOT (0, 0). The
  /// shape's fill is identical either way (a (0,0) start only adds a
  /// zero-area spur along x=0), but a stroke of the path draws that spur as a
  /// line sticking up past the banner's corner.
  static Path pathFor(Size size) {
    final double w = size.width;
    final double h = size.height;

    final Path path = Path();
    path.moveTo(0, h * 0.15);
    path.lineTo(w * 0.33, 0);
    path.lineTo(w * 0.66, h * 0.15);
    path.lineTo(w, 0);
    path.lineTo(w, h * 0.85);
    path.lineTo(w * 0.66, h);
    path.lineTo(w * 0.33, h * 0.85);
    path.lineTo(0, h);

    path.close();
    return path;
  }

  @override
  Path getClip(Size size) => pathFor(size);

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
