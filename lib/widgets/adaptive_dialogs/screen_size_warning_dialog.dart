import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';

/// Shortest window (logical pixels) the app still lays out acceptably in.
/// Below this the user is asked to expand their browser window.
const double kMinScreenHeight = 550;

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
/// too short, and takes it back down once the window is big enough again.
///
/// The warning is driven from here rather than from inside the dialog so that
/// one place decides, from one measurement, whether it should be on screen —
/// and so that closing it is a route this object holds, never "whatever is
/// currently on top of the navigator".
class ScreenSizeWarning {
  Route<void>? _route;

  /// Whether the user has already been warned about the current too-short
  /// window. Cleared when the window grows back, so the warning shows once per
  /// shrink instead of returning every time the user resizes while short.
  bool _warned = false;

  bool get isShowing => _route?.isActive ?? false;

  /// Feed the settled window height. [navigatorContext] is where the dialog is
  /// pushed from; pass null while no navigator is mounted yet.
  void onWindowHeight(double height, BuildContext? navigatorContext) {
    if (height > kMinScreenHeight) {
      _warned = false;
      dismiss();
      return;
    }

    if (_warned || isShowing || navigatorContext == null) return;
    _warned = true;
    _show(navigatorContext);
  }

  void _show(BuildContext context) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (context) => const ScreenSizeWarningDialog(),
    );
    _route = route;
    navigator.push(route).whenComplete(() {
      if (identical(_route, route)) _route = null;
    });
  }

  /// Takes the warning back down. No-op when it isn't showing — including when
  /// the user already closed it themselves.
  void dismiss() {
    final route = _route;
    _route = null;
    if (route == null || !route.isActive) return;
    route.navigator?.removeRoute(route);
  }
}

/// Asks the user to expand a too-short window. Put up and taken down by
/// [ScreenSizeWarning]; the user can also close it by hand.
class ScreenSizeWarningDialog extends StatelessWidget {
  const ScreenSizeWarningDialog({super.key});

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
        onPressed: () => Navigator.of(context).pop(),
        autofocus: true,
        child: Text(L10n.of(context).close),
      ),
    ],
  );
}
