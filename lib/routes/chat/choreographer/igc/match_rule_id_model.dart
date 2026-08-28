class MatchRuleIdModel {
  static const interactiveTranslation = "interactive_translation";

  /// Marks a match the device's spell checker found rather than the server,
  /// so the server's response can replace the whole local set when it lands.
  /// See writing-assistance.instructions.md, "Local spelling corrections".
  static const localSpellCheck = "local_spell_check";

  /// note these are not currently being passed by the server
  /// we may bring them back at some point
  static const tokenNeedsTranslation = "token_needs_translation";
  static const tokenSpanNeedsTranslation = "token_span_needs_translation";
  static const l1SpanAndGrammar = "l1_span_and_grammar";
}
