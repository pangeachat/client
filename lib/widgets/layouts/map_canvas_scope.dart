import 'package:flutter/foundation.dart';

/// Tracks whether the current route's canvas is the transparent map hole
/// ([EmptyPage]) rather than opaque content (a chat, a settings page, …).
///
/// world_v2: the persistent map lives at the base of the shell and section
/// pages render *over* it. The shell's `sideView` is go_router's nested
/// Navigator/Overlay, which absorbs pointer events even when its leaf page
/// is transparent — so to keep the map interactive underneath, the shell
/// wraps the whole `sideView` in an `IgnorePointer` while a map-canvas page
/// is showing. [EmptyPage] enters/leaves this scope on mount/unmount; the
/// counter (not a bool) survives the brief overlap when one map-canvas page
/// replaces another.
abstract class MapCanvasScope {
  static final ValueNotifier<int> _count = ValueNotifier<int>(0);

  /// Listenable for the shell. The map canvas is transparent when value > 0.
  static ValueListenable<int> get listenable => _count;

  static bool get isTransparent => _count.value > 0;

  static void enter() => _count.value++;
  static void leave() => _count.value--;
}
