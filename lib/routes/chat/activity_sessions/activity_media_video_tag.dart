import 'package:flutter/material.dart';

/// A small "this is a video" marker for the corner of an activity thumbnail on
/// compact, navigational surfaces (cards, list tiles). It differentiates a
/// video-first activity without an [ActivityMediaPlayBadge], whose centered play
/// glyph wrongly implies the video plays in place — on these surfaces tapping
/// opens the activity, where the video actually plays. See #7543.
class ActivityMediaVideoTag extends StatelessWidget {
  /// Height of the camera glyph; the chip pads around it.
  final double size;

  const ActivityMediaVideoTag({super.key, this.size = 14.0});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(size * 0.28),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(size * 0.4),
      ),
      child: Icon(Icons.videocam_rounded, size: size, color: Colors.white),
    );
  }
}
