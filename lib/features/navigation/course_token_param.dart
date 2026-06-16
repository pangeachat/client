/// Encodes a course left-panel's space id together with its active tab into a
/// single panel-token param. A `PanelToken` splits type from param on the first
/// `:` only and treats the rest as one opaque param, so a second field can't use
/// a colon — a pipe is used instead. The whole param is percent-encoded on the
/// way into the URL (so the pipe rides as `%7C`) and decoded back on parse.
/// e.g. space `!s`, tab `participants` → `!s|participants`.
abstract class CourseTokenParam {
  static String encode(String spaceLocalpart, String? tab) =>
      (tab == null || tab.isEmpty)
          ? spaceLocalpart
          : '$spaceLocalpart|$tab';

  static ({String spaceLocalpart, String? tab}) decode(String param) {
    final i = param.indexOf('|');
    if (i < 0) return (spaceLocalpart: param, tab: null);
    final tab = param.substring(i + 1);
    return (
      spaceLocalpart: param.substring(0, i),
      tab: tab.isEmpty ? null : tab,
    );
  }
}
