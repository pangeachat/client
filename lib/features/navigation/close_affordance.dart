/// Which close controls a panel (or its mobile bottom sheet) shows, derived
/// ONCE from its open-mode — never hardcoded per panel. This is the single
/// authority the column hosts and the map sheets read.
///
/// The rule (see `world-v2-architecture` → Centralized close affordance, and the
/// Figma mobile sheets where a root shows `X` only and a pushed step shows
/// `←` + `X`):
///
/// - **`X` (dismiss)** drops this panel's token entirely → reveals the map / its
///   siblings. Shown unless it would be redundant with back (the fold case).
/// - **`←` (back one step)** returns to what's *behind* this panel.
///
/// Inputs:
/// - [isPushedPage]: the panel hosts a deeper page in its own token param
///   (settings menu→page→leaf, a course card→details/invite, an add-course
///   hub→step). `←` pops one page level; `X` still dismisses the whole panel —
///   so both show, wired to different actions.
/// - [revealsMaster]: closing this panel reveals a master that sat behind it — a
///   width-**fold** (`PanelSlot.foldedOver`: the surviving detail over its folded
///   master) or, on a narrow single pane, a sibling behind the focused panel.
///   `←` reveals it; a separate `X` would do the same thing, so `X` is dropped.
///
/// Truth table:
///   root / coexisting → X only       (back F, close T)
///   folded / narrow-behind → ← only  (back T, close F)
///   pushed page / wizard step → ←+X  (back T, close T)
class CloseAffordance {
  /// Show a back arrow (returns to the parent page / folded master / sibling).
  final bool showBack;

  /// Show a close (X) that dismisses this panel to the map.
  final bool showClose;

  const CloseAffordance({required this.showBack, required this.showClose});

  factory CloseAffordance.of({
    required bool isPushedPage,
    required bool revealsMaster,
  }) =>
      CloseAffordance(
        showBack: isPushedPage || revealsMaster,
        showClose: isPushedPage || !revealsMaster,
      );
}
