/// Off the web there is no DOM focus to return — framework focus already
/// lands on the opener (see semantics_dom_focus_web.dart).
class SemanticsDomFocus {
  static SemanticsDomFocus? capture() => null;

  void restore() {}
}
