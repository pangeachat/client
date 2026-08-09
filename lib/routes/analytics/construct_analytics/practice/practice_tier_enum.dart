/// Priority tier for spaced repetition scoring.
///
/// Tier is determined by how the user most recently encountered the word
/// in chat (wa/ga/ta) and whether they've struggled with it in practice.
enum PracticeTier {
  /// User demonstrated mastery (wa) with no subsequent errors — skip entirely.
  suppressed,

  /// User needed help (ta/ga) or recently got it wrong — prioritize.
  active,

  /// Standard aging-based priority (correctly practiced, but aging).
  maintenance,
}
