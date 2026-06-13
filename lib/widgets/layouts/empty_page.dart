import 'package:flutter/material.dart';

/// The map-canvas hole (world_v2). Section roots use this as their canvas: it
/// paints nothing, so the single persistent `WorldMap` hosted by the app
/// shell ([TwoColumnLayout]) shows underneath. The shell decides — from the
/// route — to take the whole `sideView` off the hit-test tree while a
/// map-canvas route is showing, keeping the map interactive. The map is NOT
/// built here; rendering it per route is what used to remount it.
class EmptyPage extends StatelessWidget {
  const EmptyPage({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
