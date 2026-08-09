import 'package:flutter/material.dart';

/// Circular play affordance overlaid on a video or YouTube thumbnail to mark a
/// media block as playable in place. Used where tapping actually starts the
/// player: the plan-page hero poster and the media carousel. Compact,
/// navigational surfaces (cards, list tiles) use [ActivityMediaVideoTag]
/// instead, since a centered play badge there would wrongly imply tap-to-play
/// (#7543).
class ActivityMediaPlayBadge extends StatelessWidget {
  /// Diameter of the play glyph; the dark circle pads around it.
  final double size;

  const ActivityMediaPlayBadge({super.key, this.size = 32.0});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
      ),
      padding: EdgeInsets.all(size * 0.18),
      child: Icon(Icons.play_arrow_rounded, size: size, color: Colors.white),
    );
  }
}
