import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';

export 'package:fluffychat/widgets/adaptive_dialogs/window_growable_height_stub.dart'
    if (dart.library.js_interop) 'package:fluffychat/widgets/adaptive_dialogs/window_growable_height_web.dart';

/// Shortest window (logical pixels) the app still lays out acceptably in.
/// Below this the user is asked to expand their browser window.
const double kMinScreenHeight = 550;

/// Smallest gap (CSS pixels) between the OS work area and the window's outer
/// height that still counts as "the user could expand this window". Below it
/// the window effectively fills the work area — the browser is maximized or
/// fullscreen, possibly with a docked on-screen keyboard eating the bottom of
/// the screen — and asking the user to expand is asking for something the OS
/// won't give them. The slack absorbs window-manager gaps and the few pixels a
/// maximized window's borders overhang the work area by.
const double kMinGrowableHeight = 50;

/// Resize events arrive in bursts: dragging a browser window edge fires them
/// continuously, and dismissing a mobile on-screen keyboard reports a briefly
/// shrunken window before the viewport settles back to full height. Wait for
/// the measurements to stop moving before acting on them, so a transient size
/// never triggers (or hides) the warning.
const Duration kScreenSizeSettleDelay = Duration(milliseconds: 500);

/// Height of the window in logical pixels, measured from the [FlutterView]
/// rather than from [MediaQuery].
///
/// Two reasons not to use `MediaQuery.heightOf` for this:
///
/// 1. It is stale inside [WidgetsBindingObserver.didChangeMetrics]. The
///    `MediaQuery` the app installs refreshes itself from that same callback
///    via `setState`, so the new size only lands on the next frame — another
///    observer reading `MediaQuery` during the callback sees the *previous*
///    size and therefore reacts one resize behind (#8179).
/// 2. On mobile web the on-screen keyboard is reported through `viewInsets`
///    rather than by shrinking the window, so adding the bottom inset back
///    measures the window the user could actually expand. Opening or closing
///    a keyboard then never reads as "the window shrank".
double windowHeight(BuildContext context) {
  final view = View.of(context);
  return (view.physicalSize.height + view.viewInsets.bottom) /
      view.devicePixelRatio;
}

/// Whether the window is too short for the app to lay out acceptably.
bool screenIsTooShort(BuildContext context) =>
    windowHeight(context) <= kMinScreenHeight;

/// Owns the "expand your screen size" warning: puts it up when the window is
/// too short *and the user could actually make it taller*, and takes it back
/// down once either stops being true.
///
/// The expandability check is what keeps a desktop on-screen keyboard from
/// triggering the warning: a keyboard docked into the OS work area shrinks a
/// maximized browser right along with the work area, so the window still fills
/// what the OS offers and there is nothing to ask the user for (#8179 reopen).
///
/// The warning is an [OverlayEntry], never a dialog route. A route (or
/// anything else that takes focus) blurs the composer, and a focus-following
/// on-screen keyboard closes on blur — which made the original fix slam the
/// user's keyboard shut the moment it opened. Nothing here may ever move
/// focus.
class ScreenSizeWarning {
  OverlayEntry? _entry;

  /// Whether the user has already been warned about the current too-short
  /// window. Cleared when the window grows back, so the warning shows once per
  /// shrink instead of returning every time the user resizes while short.
  bool _warned = false;

  bool get isShowing => _entry != null;

  /// Feed the settled window measurements. [navigatorContext] is where the
  /// warning's overlay is found; pass null while no navigator is mounted yet.
  void onWindowMetrics({
    required double height,
    required double growableHeight,
    required BuildContext? navigatorContext,
  }) {
    if (height > kMinScreenHeight) {
      _warned = false;
      dismiss();
      return;
    }

    if (growableHeight < kMinGrowableHeight) {
      dismiss();
      return;
    }

    if (_warned || isShowing || navigatorContext == null) return;
    _warned = true;
    _show(navigatorContext);
  }

  void _show(BuildContext context) {
    final entry = OverlayEntry(
      builder: (_) => ScreenSizeWarningDialog(onClose: dismiss),
    );
    _entry = entry;
    Navigator.of(context, rootNavigator: true).overlay!.insert(entry);
  }

  /// Takes the warning back down. No-op when it isn't showing.
  void dismiss() {
    _entry?.remove();
    _entry = null;
  }
}

/// Asks the user to expand a too-short window. Put up and taken down by
/// [ScreenSizeWarning]; the user can also close it with [onClose].
///
/// Rendered in an overlay with no barrier and no focus of its own: the app —
/// including a composer whose on-screen keyboard would close if it lost
/// focus — stays fully usable underneath.
class ScreenSizeWarningDialog extends StatelessWidget {
  final VoidCallback onClose;

  const ScreenSizeWarningDialog({required this.onClose, super.key});

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    // This warning only ever shows on a short window, where the wrapped title
    // can be taller than the room the dialog has.
    scrollable: true,
    title: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 256),
      child: Text(L10n.of(context).screenSizeWarning),
    ),
    actions: [
      AdaptiveDialogAction(
        onPressed: onClose,
        child: Text(L10n.of(context).close),
      ),
    ],
  );
}
