import 'dart:js_interop';

@JS('window.addEventListener')
external void _addEventListener(String type, JSFunction listener);

extension type _Event._(JSObject _) implements JSObject {
  external void preventDefault();
}

bool _guarding = false;
bool _listening = false;

/// While [on], closing or reloading the tab asks first. Browsers show their
/// own wording for this.
void setCallLeaveGuard(bool on) {
  _guarding = on;
  if (_listening) return;
  _listening = true;
  _addEventListener(
    'beforeunload',
    ((_Event event) {
      if (_guarding) event.preventDefault();
    }).toJS,
  );
}
