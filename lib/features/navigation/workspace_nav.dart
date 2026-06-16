import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';

/// Builds workspace location strings by adding or removing panel tokens on the
/// current URL, preserving the path and every other query param. The URL is the
/// single source of truth for which panels are open (see
/// `routing.instructions.md`), so every open/close routes through here and then
/// `context.go(...)` rather than mutating app-state.
///
/// The raw query is reassembled by hand instead of via `Uri.replace`'s
/// `queryParameters`, which would percent-encode a second time and corrupt a
/// token whose param is already encoded (an encoded construct's `%7B` etc.).
abstract class WorkspaceNav {
  /// The last URL the router resolved to, so [preserveOpenPanels] can tell a
  /// left-navigation (a path change) from a panel open/close (a same-path query
  /// change). go_router's redirect only sees the destination, so the previous
  /// URL has to be remembered here.
  static Uri? _lastResolvedUri;

  /// Keep the open panels across navigation. Open panels are persistent
  /// personal companions, so a left-side navigation — a path change whose
  /// destination doesn't itself name panels — carries the previous `right=` /
  /// `left=` lists forward instead of dropping them (which is what a bare
  /// `context.go('/path')` would do). Opening or closing a panel is a same-path
  /// query change and is left exactly as written. Wired as the router's
  /// top-level redirect; returns a rewritten location or null to accept as-is.
  static String? preserveOpenPanels(Uri destination) {
    final last = _lastResolvedUri;
    final namesPanels = destination.query.split('&').any(
          (p) =>
              p == 'right' ||
              p == 'left' ||
              p.startsWith('right=') ||
              p.startsWith('left='),
        );
    // No history yet, an explicit panel set, or a same-path change → accept.
    if (last == null || namesPanels || destination.path == last.path) {
      _lastResolvedUri = destination;
      return null;
    }
    final carried = last.query
        .split('&')
        .where((p) => p.startsWith('right=') || p.startsWith('left='))
        .toList();
    if (carried.isEmpty) {
      _lastResolvedUri = destination;
      return null;
    }
    final query = [
      if (destination.query.isNotEmpty) destination.query,
      ...carried,
    ].join('&');
    final target = '${destination.path}?$query';
    // Record the rewritten target so the redirect re-run accepts it (same path).
    _lastResolvedUri = Uri.parse(target);
    return target;
  }

  /// Add [token] to the `left` list (deduped). [atStart] places it at the left
  /// edge of the column rather than the inside.
  static String openLeft(Uri current, PanelToken token, {bool atStart = false}) =>
      _mutate(current, 'left', (tokens) => _add(tokens, token, atStart));

  /// Add [token] to the `right` list (deduped). [atStart] places it to the left
  /// of the rest — a detail blooming left of its summary.
  static String openRight(Uri current, PanelToken token,
          {bool atStart = false}) =>
      _mutate(current, 'right', (tokens) => _add(tokens, token, atStart));

  static String closeLeft(Uri current, PanelToken token) =>
      _mutate(current, 'left', (tokens) => _remove(tokens, token));

  static String closeRight(Uri current, PanelToken token) =>
      _mutate(current, 'right', (tokens) => _remove(tokens, token));

  /// Replace the whole `right` list. Used when switching the analytics metric:
  /// the cluster drops the other analytics/detail tokens and seats one summary.
  static String setRight(Uri current, List<PanelToken> tokens) =>
      _mutate(current, 'right', (_) => tokens);

  static List<PanelToken> _add(
    List<PanelToken> tokens,
    PanelToken token,
    bool atStart,
  ) {
    final next = tokens.where((t) => t != token).toList();
    if (atStart) {
      next.insert(0, token);
    } else {
      next.add(token);
    }
    return next;
  }

  static List<PanelToken> _remove(List<PanelToken> tokens, PanelToken token) =>
      tokens.where((t) => t != token).toList();

  static String _mutate(
    Uri current,
    String key,
    List<PanelToken> Function(List<PanelToken>) transform,
  ) {
    final lists = parseOpenPanels(current);
    final next = transform(key == 'left' ? lists.left : lists.right);

    // Keep every other query param exactly as it appears (raw), and replace only
    // this key's segment with the freshly encoded token list.
    final parts = current.query.isEmpty ? <String>[] : current.query.split('&');
    parts.removeWhere((p) => p == key || p.startsWith('$key='));
    if (next.isNotEmpty) {
      parts.add('$key=${next.map((t) => t.encode()).join(',')}');
    }
    final query = parts.join('&');
    return query.isEmpty ? current.path : '${current.path}?$query';
  }
}
