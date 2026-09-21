import 'dart:ui' as ui show SemanticsHitTestBehavior;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_map/flutter_map.dart';

import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// Screen-reader and keyboard mirror of the drawn map pins (#7591, #8714).
///
/// The map subtree is wrapped in `ExcludeSemantics`: flutter_map's own gesture
/// detector publishes a viewport-sized tappable semantics node that blankets
/// DOM embeds layered over the map (#8013), and upstream declined to exclude
/// it (fleaflet/flutter_map#2236 — `ExcludeSemantics` around the map is their
/// recommended workaround), so the exclusion is permanent. It also drops the
/// pins' own semantics, leaving the map's "Activities" group empty to
/// assistive tech. This layer re-authors them OUTSIDE the excluded subtree:
/// one invisible semantics button per drawn pin, at the pin's projected screen
/// position, carrying the same label and tap behavior as the visual pin.
///
/// The layer is pointer-transparent by construction: none of its render
/// objects hit-test (`Semantics` boxes over empty `SizedBox`es), so pointer
/// taps and map gestures land on the real pins as before. Deliberately NOT
/// `IgnorePointer` — that strips pointer-related semantics actions (the tap)
/// from the subtree, which is the exact loss this layer exists to repair.
/// A semantics tap (what a screen-reader double-tap sends) reaches [onTap].
///
/// Flutter-side transparency is not enough on web (#7525): with the semantics
/// tree on, native clicks are hit-tested against the semantics DOM, and the
/// web engine defaults a tappable node's element to `pointer-events: all`.
/// That re-creates #8013 pin-sized: a mirror node captures native mouse
/// events for anything painted over the map at its position — an open
/// panel's inert surface, or the activity video's `<iframe>`, whose controls
/// go dead. Each pin therefore sets `hitTestBehavior: transparent`
/// (`pointer-events: none`). Screen-reader activation survives: an AT press
/// is dispatched as a DOM click AT the element, bypassing CSS pointer
/// hit-testing, and the engine forwards a standalone click on a tap-handling
/// node to the framework as a semantics tap.
///
/// Keyboard access (#8714) is the Google Maps model, per
/// world-map.instructions.md → Keyboard access: the whole layer is a SINGLE
/// Tab stop, and the arrow keys rove through the visible pins in the order
/// [cards] arrives (ranking order). Enter/Space fires the roved pin's tap;
/// Esc steps back to the group level. The pins draw to an opaque canvas, so
/// the browser cannot show a focus ring — the layer paints its own double
/// ring on the roved pin. Roving tracks the activity id, not a list index,
/// so a settle re-rank moves the ring with its pin rather than to a stranger.
class PinSemanticsLayer extends StatefulWidget {
  final MapController mapController;

  /// The pins actually drawn this frame (the budget-capped large + mid + small
  /// set), in the order they should be announced.
  final List<QuestActivityCard> cards;
  final ActivityPinState Function(String activityId) stateOf;
  final void Function(QuestActivityCard card) onTap;

  /// The live-session seat summary for a pin ("2 of 4 players"), or null for
  /// a pin with no live session. Supplied by the view from the same
  /// participant derivation the drawn cards use, so the announced and drawn
  /// counts can never drift (#8753).
  final String? Function(QuestActivityCard card)? liveDetailOf;

  const PinSemanticsLayer({
    super.key,
    required this.mapController,
    required this.cards,
    required this.stateOf,
    required this.onTap,
    this.liveDetailOf,
  });

  @override
  State<PinSemanticsLayer> createState() => PinSemanticsLayerState();
}

class PinSemanticsLayerState extends State<PinSemanticsLayer> {
  /// Marks the painted focus ring for tests.
  static const ringKey = ValueKey('pin_focus_ring');

  /// The ring pair is deliberately NOT theme tokens: it must hold non-text
  /// contrast (WCAG 1.4.11) over arbitrary tile imagery in both themes, and
  /// white-inside-near-black does that on any backdrop.
  static const Color _ringInner = Colors.white;
  static const Color _ringOuter = Color(0xDD000000);
  static const double _ringStroke = 2.0;

  final FocusNode _focusNode = FocusNode(debugLabel: 'PinSemanticsLayer');

  /// The roved pin's activity id, or null at the group level (no ring).
  final ValueNotifier<String?> _rovedActivityId = ValueNotifier(null);

  /// The culled, in-viewport pins of the last build, in announcement
  /// (ranking) order — the set the arrow keys rove. A build-time snapshot so
  /// the key handler and the builder can never disagree about what is
  /// visible; the camera StreamBuilder keeps it fresh.
  List<QuestActivityCard> _visibleCards = const [];

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _rovedActivityId.dispose();
    super.dispose();
  }

  /// Entering the group roves the highest-ranked visible pin immediately, so
  /// Tab lands somewhere visible rather than on an invisible container — an
  /// unmarked focusable is exactly the 2.4.7 failure this feature repairs.
  void _onFocusChanged() {
    _rovedActivityId.value = _focusNode.hasFocus
        ? _visibleCards.firstOrNull?.activityId
        : null;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      return _rove(1);
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      return _rove(-1);
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      final card = _rovedCard;
      if (card == null) return KeyEventResult.ignored;
      widget.onTap(card);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && _rovedActivityId.value != null) {
      _rovedActivityId.value = null;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  QuestActivityCard? get _rovedCard {
    final id = _rovedActivityId.value;
    if (id == null) return null;
    for (final card in _visibleCards) {
      if (card.activityId == id) return card;
    }
    return null;
  }

  /// Moves the roving ring by [delta] within the visible set, clamped at the
  /// ends (no wraparound — losing your place in a long list disorients). A
  /// roved pin the camera has since culled resolves to no index, and roving
  /// restarts from the top instead of dropping focus.
  KeyEventResult _rove(int delta) {
    if (_visibleCards.isEmpty) return KeyEventResult.ignored;
    final current = _rovedCard;
    final index = current == null ? -1 : _visibleCards.indexOf(current);
    final next = index < 0
        ? 0
        : (index + delta).clamp(0, _visibleCards.length - 1);
    _rovedActivityId.value = _visibleCards[next].activityId;
    return KeyEventResult.handled;
  }

  /// The live camera, or null before the map is laid out (reading it throws
  /// until then). Pins only exist after `onMapReady`, so a null camera can
  /// only coincide with an empty [PinSemanticsLayer.cards].
  MapCamera? get _camera {
    try {
      return widget.mapController.camera;
    } catch (_) {
      return null;
    }
  }

  /// The announced pin: title, language and level (what the expanded card
  /// shows visually — announced on every pin since a card's content has no
  /// semantics of its own, #8753/#8646), the live seat count where one
  /// exists, then the status.
  String _labelOf(L10n l10n, QuestActivityCard card) => [
    l10n.activityLabel(card.title),
    PLanguageStore.byLangCode(card.l2)?.displayName ?? card.l2,
    ?card.cefr,
    ?widget.liveDetailOf?.call(card),
    widget.stateOf(card.activityId).label(l10n),
  ].join(', ');

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ValueListenableBuilder<String?>(
      valueListenable: _rovedActivityId,
      builder: (context, rovedId, _) {
        return Semantics(
          label: l10n.activities,
          hint: l10n.mapPinsKeyboardHint,
          // Announce the roved pin as the arrow keys move (a keyboard +
          // screen-reader user gets no other signal — the ring is visual).
          value: _rovedCard == null ? null : _labelOf(l10n, _rovedCard!),
          liveRegion: rovedId != null,
          container: true,
          // Focus INSIDE the container so its focusable/focused semantics
          // merge up into this labeled group node — outside, they would land
          // on an unlabeled ancestor: a nameless Tab stop, the defect #8714
          // exists to remove.
          child: Focus(
            focusNode: _focusNode,
            onKeyEvent: _onKeyEvent,
            // An empty layer must not be a (dead) Tab stop.
            canRequestFocus: widget.cards.isNotEmpty,
            // Follow the camera: pan/zoom moves the mirror nodes with their
            // pins.
            child: StreamBuilder(
              stream: widget.mapController.mapEventStream,
              builder: (context, _) {
                final camera = _camera;
                if (camera == null) return const SizedBox.shrink();
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.biggest;
                    // One fixed touch-target box per pin, centered on its
                    // point — the screen-reader focus highlight lands on the
                    // pin but does not trace a teardrop's or large card's
                    // exact drawn rect. Deliberate: per-tier rect mirroring
                    // was tried (#8646) and dropped for simplicity; restore
                    // it from there if QA needs the highlight to hug the
                    // larger tiers.
                    const box = PinSize.dotTouchTarget;
                    final visible = <QuestActivityCard>[];
                    final children = <Widget>[];
                    Offset? rovedOffset;
                    for (final card in widget.cards) {
                      final point = card.point;
                      if (point == null) continue;
                      final offset = camera.latLngToScreenOffset(point);
                      // Off-viewport pins (the camera moved since the last
                      // settle re-rank) publish nothing, like the marker
                      // layers' culling.
                      if (offset.dx < 0 ||
                          offset.dy < 0 ||
                          offset.dx > size.width ||
                          offset.dy > size.height) {
                        continue;
                      }
                      visible.add(card);
                      if (card.activityId == rovedId) rovedOffset = offset;
                      children.add(
                        Positioned(
                          left: offset.dx - box / 2,
                          top: offset.dy - box / 2,
                          width: box,
                          height: box,
                          child: Semantics(
                            // Each pin is its own node; without this a lone
                            // pin merges into the "Activities" group node and
                            // its label gets the group's prefixed onto it.
                            container: true,
                            button: true,
                            // Web: keep the node's DOM element out of native
                            // pointer hit-testing (see the class doc, #7525)
                            // — AT activation arrives as a targeted click,
                            // not a hit-tested one, so it still lands.
                            hitTestBehavior:
                                ui.SemanticsHitTestBehavior.transparent,
                            label: _labelOf(l10n, card),
                            onTap: () => widget.onTap(card),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      );
                    }
                    _visibleCards = visible;
                    if (rovedOffset != null) {
                      // The authored focus ring (#8714): the canvas gets no
                      // browser ring, so the layer paints its own. Purely
                      // visual — no semantics, no pointer.
                      children.add(
                        Positioned(
                          left: rovedOffset.dx - box / 2,
                          top: rovedOffset.dy - box / 2,
                          width: box,
                          height: box,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              key: ringKey,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _ringOuter,
                                  width: _ringStroke,
                                ),
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _ringInner,
                                    width: _ringStroke,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    return Stack(children: children);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}
