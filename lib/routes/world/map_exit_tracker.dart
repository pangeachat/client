/// Per-tier bookkeeping for the map's pin pop-in / shrink-out animations,
/// shared by the small/mid dot tier and the large-card tier of
/// [WorldMapView](world_map_view.dart). One instance owns three things for its
/// tier: which snapshots are currently animating out ([exiting]), which ids
/// have already played their entry pop-in ([markEntered]), and the previous
/// frame's active set that the two are derived from.
///
/// The rule that shapes it, and the reason it is its own class rather than
/// inline state, is that **only an on-screen item may animate out**:
/// flutter_map's `MarkerLayer` culls markers outside the camera, so a dying
/// marker off screen is never built, never runs its animation controller and
/// never fires its `onExited` callback. Queueing one therefore strands it here
/// forever; panning back over it builds it fresh, and the dying branch of
/// [WorldMapDot](world_map_state_dot.dart) /
/// [WorldMapLargeCardAnimated](world_map_large_card.dart) replays the shrink
/// from full scale — a phantom pin that collapses (repeatedly, as the layer
/// culls and reorders) before the real one pops in at the settle (#8155).
///
/// So an item that leaves the active set because the camera panned away is
/// dropped outright — there is nothing on screen to animate — while one that
/// leaves for a *ranking* reason (demoted past the width budget's cap, promoted
/// to a large card, filtered out) is still visible and earns its shrink-out.
/// See world-map.instructions.md ("Pin display").
class MapExitTracker<T> {
  final Map<String, T> _exiting = {};
  Map<String, T> _lastActive = const {};
  final Set<String> _entered = {};

  /// The snapshots currently animating out, in the order they left.
  List<T> get exiting => _exiting.values.toList();

  /// True the first time [id] is seen — the item plays its entry animation on
  /// exactly that build, and renders settled on every later one. A `MarkerLayer`
  /// State discarded and recreated mid-gesture must not replay its pop-in
  /// (#8136).
  bool markEntered(String id) => _entered.add(id);

  /// Drop [id]'s exit once its animation has finished and its widget has
  /// reported back.
  void finishExit(String id) => _exiting.remove(id);

  /// Reconcile against this frame's [active] set — id to render snapshot —
  /// deciding which items start (or abandon) a shrink-out. [isOnScreen] answers
  /// whether a snapshot's map point currently falls inside the camera; see the
  /// class doc for why it gates both halves.
  ///
  /// Called during build, so it must not call setState: it only mutates this
  /// tracker's own maps, and the layers are built from the result in the same
  /// frame.
  void update({
    required Map<String, T> active,
    required bool Function(T snapshot) isOnScreen,
  }) {
    // Re-appeared in the active set: cancel any in-progress exit. Scrolled off
    // screen: drop it, the exit can no longer play.
    _exiting.removeWhere(
      (id, snapshot) => active.containsKey(id) || !isOnScreen(snapshot),
    );

    // An item gone from the active set forgets its "already entered" mark, so
    // its next appearance pops in fresh. While the camera is moving the view
    // holds its last-settled render model, so the id set — and this — doesn't
    // churn mid-gesture (#8136).
    _entered.retainAll(active.keys);

    // Anything active last frame, gone this frame, and still on screen starts
    // its shrink-out from its last-known render state.
    for (final entry in _lastActive.entries) {
      if (!active.containsKey(entry.key) &&
          !_exiting.containsKey(entry.key) &&
          isOnScreen(entry.value)) {
        _exiting[entry.key] = entry.value;
      }
    }

    _lastActive = active;
  }
}
