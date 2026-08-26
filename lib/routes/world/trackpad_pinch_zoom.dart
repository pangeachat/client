import 'package:flutter/gestures.dart';

/// Turns a trackpad pinch into a map zoom (#8556).
///
/// A browser reports a two-finger trackpad pinch as a ctrl-modified wheel
/// event, which Flutter web delivers as a [PointerScaleEvent] carrying the
/// factor the gesture scaled by. flutter_map answers only the plain wheel
/// ([PointerScrollEvent]), so nothing on the map responds to a pinch — on a
/// laptop that leaves the on-map +/- controls as the only way to zoom.
///
/// Hand a map's pointer signals ([Listener.onPointerSignal]) to this, and it
/// calls [onPinch] with the gesture's scale factor and the cursor's position
/// within the listener. Any other signal — the wheel above all — is left for
/// the map to handle as before. The claim goes through the shared
/// [PointerSignalResolver], whose innermost registrant wins, so this yields
/// automatically the day flutter_map reads the event itself.
void claimTrackpadPinch(
  PointerSignalEvent event,
  void Function(double scale, Offset focalPoint) onPinch,
) {
  if (event is! PointerScaleEvent) return;
  GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
    resolved as PointerScaleEvent;
    onPinch(resolved.scale, resolved.localPosition);
  });
}
