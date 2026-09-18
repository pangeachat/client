import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsSortKey;

import 'package:fluffychat/features/navigation/panel_entry_intent.dart';

/// A workspace panel's named group (routing.instructions.md, "Every panel is
/// a named group to assistive tech"), and where a panel the learner just
/// opened from the user cluster or the rail lands: the group itself, so a
/// screen reader announces the page, claimed one discrete beat after the
/// panel mounts — the delay `OnboardingPageGroup` uses, past the web engine's
/// view-host focus hop (#8769). The group is never a Tab stop, so the next Tab
/// reaches the panel's first control. Only a mount that finds
/// [PanelEntryIntent] armed claims; every other way a panel opens leaves focus
/// where it was.
class PanelEntryFocus extends StatefulWidget {
  final String label;
  final SemanticsSortKey sortKey;
  final Widget child;

  /// This panel's identity for an arm that names its target (its panel type),
  /// so it can claim while already on screen. Null for a panel no arm names.
  final Object? panel;

  /// Test seam; the app uses [PanelEntryIntent.instance].
  final PanelEntryIntent? intent;

  const PanelEntryFocus({
    required this.label,
    required this.sortKey,
    required this.child,
    this.panel,
    this.intent,
    super.key,
  });

  static const Duration claimDelay = Duration(milliseconds: 300);

  @override
  State<PanelEntryFocus> createState() => _PanelEntryFocusState();
}

class _PanelEntryFocusState extends State<PanelEntryFocus> {
  // Focusable by claim and by assistive tech, never by Tab.
  final FocusNode _node = FocusNode(
    debugLabel: 'PanelEntryFocus',
    skipTraversal: true,
  );
  Timer? _claim;

  PanelEntryIntent get _intent => widget.intent ?? PanelEntryIntent.instance;

  @override
  void initState() {
    super.initState();
    _node.addListener(_rebuild);
    _intent.addListener(_onArmed);
    if (_intent.take(panel: widget.panel)) _scheduleClaim();
  }

  /// Already on screen, so only an arm that names this panel is its to take.
  void _onArmed() {
    if (_intent.take(panel: widget.panel, mounting: false)) _scheduleClaim();
  }

  void _scheduleClaim() {
    _claim?.cancel();
    _claim = Timer(PanelEntryFocus.claimDelay, _node.requestFocus);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _intent.removeListener(_onArmed);
    _claim?.cancel();
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      container: true,
      // Browse-order key on the group itself (#8755): a key on an unlabeled
      // wrapper formed an extra node VoiceOver reordered heuristically.
      sortKey: widget.sortKey,
      // Keep descendants as their own nodes: without this, loose text with no
      // container of its own (the Level drilldown's "LVL 15 … XP" header)
      // merges INTO the panel's name, announcing as one garbled label.
      explicitChildNodes: true,
      focusable: true,
      focused: _node.hasPrimaryFocus,
      onFocus: _node.requestFocus,
      child: Focus(
        focusNode: _node,
        includeSemantics: false,
        child: widget.child,
      ),
    );
  }
}
