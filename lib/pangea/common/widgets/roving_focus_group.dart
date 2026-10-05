import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One Tab stop for a list of like controls, with the arrow keys moving focus
/// between them — the roving-tabindex pattern, per
/// accessibility.instructions.md → One Tab stop per list (#8877).
///
/// Items resolve their [FocusNode] with [RovingFocusGroup.nodeOf] and hand it
/// to their own InkWell/ListTile, so focus, the highlight and Enter/Space stay
/// the control's own. Only the group's *entry* item is Tab-traversable: the
/// item last focused here, else [selectedId], else the first item that is
/// built — a selected item scrolled out of a lazy list would otherwise leave
/// the whole list with no Tab stop. Up/Down move to the neighbour in [ids]
/// order, clamped at the ends (no wrap — losing your place in a long list
/// disorients); Left/Right are aliases for the same previous/next step, so a
/// grid or a wrapping row of chips roves like every other list.
class RovingFocusGroup extends StatefulWidget {
  /// The items, in arrow-key order.
  final List<String> ids;

  /// The item Tab lands on until one has been focused here: the open chat, the
  /// lit rail section.
  final String? selectedId;

  final Widget child;

  const RovingFocusGroup({
    required this.ids,
    required this.child,
    this.selectedId,
    super.key,
  });

  /// The focus node for item [id]. Call from a build below the group.
  static FocusNode nodeOf(BuildContext context, String id) {
    final scope = context.getInheritedWidgetOfExactType<_RovingFocusScope>();
    assert(scope != null, 'RovingFocusGroup.nodeOf called outside a group');
    return scope!.state._nodeFor(id);
  }

  @override
  State<RovingFocusGroup> createState() => _RovingFocusGroupState();
}

class _RovingFocusGroupState extends State<RovingFocusGroup> {
  // ponytail: nodes for ids that leave [ids] stay until dispose — detached,
  // so never an entry and never focused; a list sees a few hundred ids at most.
  final Map<String, _RovingFocusNode> _nodes = {};

  /// The item last focused inside the group, which Tab returns to.
  String? _lastFocusedId;

  @override
  void didUpdateWidget(RovingFocusGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new selection (a chat opened, a section switched) is where Tab lands.
    if (widget.selectedId != oldWidget.selectedId) _lastFocusedId = null;
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  _RovingFocusNode _nodeFor(String id) {
    assert(widget.ids.contains(id), 'roving item "$id" is not in ids');
    return _nodes.putIfAbsent(id, () {
      final node = _RovingFocusNode(id, this);
      node.addListener(() {
        if (node.hasPrimaryFocus) _lastFocusedId = id;
      });
      return node;
    });
  }

  /// A node is built once the item's Focus widget has parented it.
  bool _isBuilt(String id) => _nodes[id]?.parent != null;

  /// The one item Tab may land on, decided at traversal time.
  String? get _entryId {
    final preferred = _lastFocusedId ?? widget.selectedId;
    if (preferred != null && _isBuilt(preferred)) return preferred;
    for (final id in widget.ids) {
      if (_isBuilt(id)) return id;
    }
    return null;
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    // Left/Right are aliases for previous/next in list order, not a second
    // axis: the vocab grid and the grammar chips wrap across rows, so a
    // learner reaches for whichever pair matches the layout in front of them
    // and both walk the one order the list is built in (#8935). Flipped under
    // an RTL directionality, where next reads leftwards.
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.arrowRight => rtl ? -1 : 1,
      LogicalKeyboardKey.arrowLeft => rtl ? 1 : -1,
      _ => 0,
    };
    if (delta == 0) return KeyEventResult.ignored;
    final focused = _nodes.values.where((n) => n.hasPrimaryFocus).firstOrNull;
    if (focused == null) return KeyEventResult.ignored;
    final index = widget.ids.indexOf(focused.id);
    if (index < 0) return KeyEventResult.ignored;

    final target = _nodeFor(
      widget.ids[(index + delta).clamp(0, widget.ids.length - 1)],
    );
    if (target.parent == null) {
      // The neighbour sits beyond the lazy list's cache: bring the focused row
      // to the viewport edge so the neighbour builds, and the next press
      // reaches it.
      Scrollable.ensureVisible(focused.context!, alignment: delta > 0 ? 0 : 1);
      return KeyEventResult.handled;
    }
    FocusTraversalPolicy.defaultTraversalRequestFocusCallback(
      target,
      alignmentPolicy: delta > 0
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    // Focusable only as an ancestor: it never takes focus or a Tab stop of its
    // own, it only hears the arrow keys bubbling up from a focused item.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: _RovingFocusScope(state: this, child: widget.child),
    );
  }
}

class _RovingFocusScope extends InheritedWidget {
  final _RovingFocusGroupState state;

  const _RovingFocusScope({required this.state, required super.child});

  @override
  bool updateShouldNotify(_RovingFocusScope oldWidget) => false;
}

/// A focus node whose Tab-traversability is decided at traversal time: only
/// the group's entry item is traversable, so Tab visits the list once. (The
/// stored flag the Focus widget writes back is ignored on purpose.)
class _RovingFocusNode extends FocusNode {
  final String id;
  final _RovingFocusGroupState group;

  _RovingFocusNode(this.id, this.group) : super(debugLabel: 'roving:$id');

  @override
  bool get skipTraversal => id != group._entryId;
}
