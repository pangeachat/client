/// Raw `key=value` surgery on a workspace URL's query string.
///
/// The workspace query is reassembled by hand — split on `&`, drop/append whole
/// `key=value` segments, rejoin — and deliberately NOT through
/// `Uri.replace(queryParameters:)`, which percent-encodes a second time and
/// corrupts a token param that is already encoded: a `m=course:!id` filter's
/// `:`/`!` (`%3A`/`%21`), or a construct detail's `%7B…%7D`. This is the single
/// home for that pattern; every redirect / panel / nav helper that edits the
/// query routes through here instead of re-deriving (and re-explaining) it. See
/// `routing.instructions.md`.
abstract class WorkspaceQuery {
  /// The raw `key=value` segments of [query] (empty when there are none),
  /// each kept verbatim so an already-encoded param is not touched.
  static List<String> parts(String query) =>
      query.isEmpty ? <String>[] : query.split('&');

  /// The value of the first `key=value` segment in [query] whose key is [key],
  /// or null when [key] is absent; a bare `key` flag (no `=`) yields `''`. The
  /// value is returned verbatim (still percent-encoded), like the segments
  /// [parts] keeps. Read-only — pair with [removeKeys] when you also drop it.
  static String? valueOf(String query, String key) {
    for (final p in parts(query)) {
      final eq = p.indexOf('=');
      if ((eq < 0 ? p : p.substring(0, eq)) == key) {
        return eq < 0 ? '' : p.substring(eq + 1);
      }
    }
    return null;
  }

  /// Drop in place every segment whose key is in [keys] — a bare `key` flag or a
  /// `key=value` pair. The key is the text before the first `=`, so `key=` never
  /// matches a different key that merely shares a prefix (`left` vs `leftish`).
  static void removeKeys(List<String> parts, Set<String> keys) =>
      parts.removeWhere((p) {
        final eq = p.indexOf('=');
        return keys.contains(eq < 0 ? p : p.substring(0, eq));
      });

  /// Compose a location from [path] and raw query [parts], dropping the `?`
  /// entirely when there is nothing to carry.
  static String location(String path, List<String> parts) =>
      parts.isEmpty ? path : '$path?${parts.join('&')}';
}
