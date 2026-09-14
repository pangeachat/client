/// Why a panel is drawn at its **floor** — its collapsed state — rather than
/// its full surface. The course panel is the only one with a floor, and its
/// floor is the course context bar (world-map.instructions.md).
///
/// Both cases draw the same surface; they differ only in whether the learner
/// can move out of it, which decides whether the floor's chevron is offered
/// at all (#9037).
enum PanelFloor {
  /// The learner collapsed it — under a `?c=` context, an absent `course`
  /// token IS the collapsed state (routing.instructions.md → Reading a
  /// workspace URL). The chevron expands it again.
  chosen,

  /// The width budget degraded it here instead of folding it away, so the
  /// course keeps naming the map it scopes. There is no expanded state to move
  /// to at this width — the budget would just degrade it again — so the floor
  /// offers no chevron: a control that cannot do what it says is worse than
  /// none. The learner's own choice still rides the URL and takes effect when
  /// width returns.
  imposed,
}
