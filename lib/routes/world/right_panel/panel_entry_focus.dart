import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/features/navigation/panel_entry_intent.dart';

/// Lands keyboard focus inside a panel the learner just opened from the user
/// cluster: the panel's first control in Tab order (today its header's close
/// or back button), claimed one discrete beat after the panel mounts — the
/// delay `OnboardingPageGroup` uses, past the web engine's view-host focus
/// hop (#8769). Only a mount that finds [PanelEntryIntent] armed claims;
/// every other way a panel opens leaves focus where it was
/// (routing.instructions.md, "Every panel is a named group to assistive
/// tech").
class PanelEntryFocus extends StatefulWidget {
  final Widget child;

  /// Test seam; the app uses [PanelEntryIntent.instance].
  final PanelEntryIntent? intent;

  const PanelEntryFocus({required this.child, this.intent, super.key});

  static const Duration claimDelay = Duration(milliseconds: 300);

  @override
  State<PanelEntryFocus> createState() => _PanelEntryFocusState();
}

class _PanelEntryFocusState extends State<PanelEntryFocus> {
  // Never a Tab stop and never focused itself: it only scopes the search for
  // the panel's first control.
  final FocusNode _root = FocusNode(
    debugLabel: 'PanelEntryFocus',
    skipTraversal: true,
    canRequestFocus: false,
  );
  Timer? _claim;

  @override
  void initState() {
    super.initState();
    if ((widget.intent ?? PanelEntryIntent.instance).take()) {
      _claim = Timer(PanelEntryFocus.claimDelay, _claimFirstControl);
    }
  }

  /// The first control in reading order: the top-most band of the panel's
  /// traversable nodes, then its leading edge. (The traversal policy's own
  /// sort is protected API; this is the same rule for a panel header.)
  void _claimFirstControl() {
    if (!mounted) return;
    final nodes = _root.traversalDescendants.toList();
    if (nodes.isEmpty) return;
    final topMost = nodes.reduce((a, b) => a.rect.top <= b.rect.top ? a : b);
    final band = nodes.where(
      (n) =>
          n.rect.top < topMost.rect.bottom && n.rect.bottom > topMost.rect.top,
    );
    final rtl = Directionality.of(context) == TextDirection.rtl;
    band
        .reduce(
          (a, b) => rtl
              ? (a.rect.right >= b.rect.right ? a : b)
              : (a.rect.left <= b.rect.left ? a : b),
        )
        .requestFocus();
  }

  @override
  void dispose() {
    _claim?.cancel();
    _root.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: _root, includeSemantics: false, child: widget.child);
}
