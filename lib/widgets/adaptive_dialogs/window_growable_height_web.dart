import 'dart:js_interop';

@JS('outerHeight')
external double get _outerHeight;

@JS('screen')
external _DomScreen get _screen;

extension type _DomScreen(JSObject _) implements JSObject {
  external double get availHeight;
}

/// How much taller the browser window could get if the user expanded it: the
/// height of the OS work area (`screen.availHeight` — the display minus
/// taskbars and *docked windows*, which includes a docked on-screen keyboard)
/// minus the window's full outer height.
///
/// Both values are unscaled CSS pixels — unlike the logical pixels
/// [windowHeight] reports, they don't move with browser zoom — so they are only
/// compared with each other, never with a logical-pixel measurement.
double windowGrowableHeight() => _screen.availHeight - _outerHeight;
