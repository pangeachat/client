import 'package:flutter/foundation.dart';

/// The single live left-column panel's focus signal.
///
/// The shell ([WorkspaceShell]) sets [focusedLeftToken] from the URL's `?left=`
/// head every frame; a focusable left surface (today only a room's
/// `ChatController`) listens and compares against its own encoded token to learn
/// "am I the focused panel right now" without reading the router. This replaces
/// `ChatController`'s old `GoRouter.routeInformationProvider` subscription, which
/// fired teardown on *every* route change — so left-navigation that merely
/// reorders or adds panels no longer tears the live chat down.
///
/// By the one-live-session rule (see `routing.instructions.md`) at most one
/// `room:` token is ever live, so a single token string is enough; null means no
/// room panel is focused (a course/settings surface, the map, or narrow mode).
class PanelFocusController extends ChangeNotifier {
  PanelFocusController._();

  static final PanelFocusController instance = PanelFocusController._();

  String? _focusedLeftToken;
  String? get focusedLeftToken => _focusedLeftToken;

  /// Sets the focused token. A no-op (no notification) when unchanged, so a
  /// shell rebuild that doesn't move focus doesn't churn listeners.
  void set(String? token) {
    if (token == _focusedLeftToken) return;
    _focusedLeftToken = token;
    notifyListeners();
  }
}
