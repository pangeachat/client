import 'dart:math';

import 'package:flutter/widgets.dart';

/// Tracks how much of the activity's media carousel is on screen in the chat
/// timeline, so [ActivityChatBackground] can fade the activity image in only
/// once the carousel has scrolled away (see activities.instructions.md).
///
/// The carousel registers itself through [ActivityMediaVisibilityTarget].
/// Listeners hear that the carousel's position may have changed — it mounted,
/// unmounted, or the timeline's layout moved — and read [visibleFraction]
/// once layout has settled. Scrolling itself is heard from the timeline's
/// scroll controller.
class ActivityMediaVisibility extends ChangeNotifier {
  BuildContext? _target;
  bool _disposed = false;

  void attach(BuildContext target) {
    _target = target;
    notifyListeners();
  }

  void detach(BuildContext target) {
    if (_disposed || _target != target) return;
    _target = null;
    notifyListeners();
  }

  /// The timeline's layout changed without a scroll (new messages, history
  /// loading, a resize), which can move the carousel.
  void markLayoutChanged() {
    if (!_disposed) notifyListeners();
  }

  /// The share of the carousel's height inside the timeline's viewport, from 0
  /// (off screen, or not in the timeline at all) to 1 (fully visible). Read it
  /// after layout, never during build.
  double get visibleFraction {
    final target = _target;
    if (target == null) return 0;
    final box = target.findRenderObject();
    final viewport = target
        .findAncestorStateOfType<ScrollableState>()
        ?.context
        .findRenderObject();
    if (box is! RenderBox ||
        viewport is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        !viewport.hasSize ||
        box.size.height <= 0) {
      return 0;
    }
    final height = box.size.height;
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final visible = min(top + height, viewport.size.height) - max(top, 0.0);
    return visible.clamp(0.0, height) / height;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
