import 'package:latlong2/latlong.dart';

/// Shared camera memory for the interim per-route [WorldMap] instances
/// (world_v2 map architecture): each remount restores the last view so
/// section switches feel like one continuous map. Superseded when the
/// persistent shell map lands.
abstract class WorldCameraState {
  static LatLng? lastCenter;
  static double? lastZoom;

  static void remember(LatLng center, double zoom) {
    lastCenter = center;
    lastZoom = zoom;
  }
}
