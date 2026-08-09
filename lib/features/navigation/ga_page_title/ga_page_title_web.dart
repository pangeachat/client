import 'dart:js_interop';

@JS('gtag')
external JSFunction? get _gtag;

/// Point GA's page_title field at the current workspace screen name WITHOUT
/// touching the visible document.title, which stays "Pangea Chat"
/// (google-analytics.instructions.md). gtag('set') applies to all subsequent
/// hits on the page, so page_views and screen_views report the token screen
/// name while the browser tab keeps the app name.
///
/// gtag is absent when Firebase analytics init was skipped (no env config,
/// e.g. local dev) — no-op in that case.
void setGaPageTitle(String name) {
  final gtag = _gtag;
  if (gtag == null) return;
  gtag.callAsFunction(null, 'set'.toJS, {'page_title': name}.jsify());
}
