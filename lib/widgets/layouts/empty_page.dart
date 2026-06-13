import 'package:flutter/material.dart';

import 'package:fluffychat/widgets/layouts/map_canvas_scope.dart';

/// The map-canvas hole (world_v2). Section roots use this as their canvas:
/// it paints nothing, so the single persistent [WorldMap] hosted by the app
/// shell ([TwoColumnLayout]) shows underneath. While mounted it marks the
/// canvas as transparent ([MapCanvasScope]) so the shell makes the whole
/// `sideView` gesture-pass-through and the map stays interactive. The map is
/// NOT built here — rendering it per route is what used to remount it.
class EmptyPage extends StatefulWidget {
  const EmptyPage({super.key});

  @override
  State<EmptyPage> createState() => _EmptyPageState();
}

class _EmptyPageState extends State<EmptyPage> {
  @override
  void initState() {
    super.initState();
    MapCanvasScope.enter();
  }

  @override
  void dispose() {
    MapCanvasScope.leave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
