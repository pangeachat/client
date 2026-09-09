import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsSortKey;

import 'package:fluffychat/features/navigation/panel_entry_intent.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/routes/world/panel_card.dart';

/// A right-column panel's named group (routing.instructions.md, "Every panel
/// is a named group to assistive tech"), and where a panel the learner just
/// opened from the user cluster lands: the group itself, so a screen reader
/// announces the page, claimed one discrete beat after the panel mounts — the
/// delay `OnboardingPageGroup` uses, past the web engine's view-host focus hop
/// (#8769). The group is never a Tab stop, so the next Tab reaches the panel's
/// first control. Only a mount that finds [PanelEntryIntent] armed claims;
/// every other way a panel opens leaves focus where it was.
///
/// While the group holds that focus the panel wears the standard focus ring,
/// published through [PanelEntryRing] and drawn by [PanelCard], which owns the
/// card's outline. Without it a sighted keyboard user watches focus vanish for
/// a press: the group is not a control, so nothing on screen said where the
/// highlight had gone.
class PanelEntryFocus extends StatefulWidget {
  final String label;
  final SemanticsSortKey sortKey;
  final Widget child;

  /// Test seam; the app uses [PanelEntryIntent.instance].
  final PanelEntryIntent? intent;

  const PanelEntryFocus({
    required this.label,
    required this.sortKey,
    required this.child,
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

  @override
  void initState() {
    super.initState();
    _node.addListener(_rebuild);
    FocusManager.instance.addHighlightModeListener(_onHighlightModeChanged);
    if ((widget.intent ?? PanelEntryIntent.instance).take()) {
      _claim = Timer(PanelEntryFocus.claimDelay, _node.requestFocus);
    }
  }

  void _rebuild() => setState(() {});

  void _onHighlightModeChanged(FocusHighlightMode _) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _claim?.cancel();
    FocusManager.instance.removeHighlightModeListener(_onHighlightModeChanged);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      container: true,
      // Browse-order key on the group itself (#8755) — see WorkspaceLeftPanel.
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
        // An inherited signal, not a rebuild of the subtree: the panel below
        // is the same widget instance across a focus change, so only a
        // dependency reaches the card.
        child: PanelEntryRing(
          showRing:
              _node.hasPrimaryFocus && FocusRingTapTarget.highlightsEnabled,
          child: widget.child,
        ),
      ),
    );
  }
}
