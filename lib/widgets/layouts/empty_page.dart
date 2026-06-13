import 'package:flutter/material.dart';

/// The map-canvas hole (world_v2). Section roots use this as their canvas:
/// it is fully transparent and lets pointer events through, so the single
/// persistent [WorldMap] hosted by the app shell ([TwoColumnLayout]) shows
/// and stays interactive underneath. The map is NOT built here anymore —
/// rendering it per route is what used to remount it on every navigation.
class EmptyPage extends StatelessWidget {
  const EmptyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(child: SizedBox.expand());
  }
}
