import 'package:flutter/material.dart';

import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// The clustered-pins bubble (Google-Maps grouping), coloured by the cluster's
/// dominant state so a cluster with an open session reads green. Animates in
/// from scale 0; the count label is hidden until the bubble is nearly full-size
/// so the number doesn't appear to hang in mid-air.
class WorldMapClusterBubble extends StatefulWidget {
  final int count;
  final ActivityPinState dominant;

  /// When false the bubble starts fully visible (no scale-in). Set to false
  /// while the camera is moving so cluster regroupings from zoom threshold
  /// crossings don't pop-animate.
  final bool animate;

  const WorldMapClusterBubble({
    super.key,
    required this.count,
    required this.dominant,
    this.animate = true,
  });

  @override
  State<WorldMapClusterBubble> createState() => _WorldMapClusterBubbleState();
}

class _WorldMapClusterBubbleState extends State<WorldMapClusterBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final CurvedAnimation _curved;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    if (widget.animate) {
      _ctrl.forward();
    } else {
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      builder: (context, _) => Transform.scale(
        scale: _curved.value,
        child: Container(
          decoration: BoxDecoration(
            color: widget.dominant.color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
          ),
          alignment: Alignment.center,
          child: _curved.value >= 0.8
              ? Text(
                  '${widget.count}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
