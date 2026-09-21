import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';

/// The playing activity video as one named Tab stop that answers YouTube's own
/// keys — Space, Enter or K to play and pause, M to mute, C for captions
/// (#9128; design in activities.instructions.md).
///
/// Focus stays here and never enters the player: on web the player is a
/// platform view whose own focus node is a dead Tab stop, and Tab cannot reach
/// the frame behind it, so everything inside [child] is kept out of focus
/// traversal.
///
/// The node is a plain named group, never a button. A button's children are
/// presentational on web, and the embed's frame — which a screen reader can
/// still walk into — is one of them.
///
/// The ring is the two-tone pair because it sits beside arbitrary video
/// frames, and it is laid out around [child] rather than over it, so no
/// Flutter layer is ever composited above the embed.
class ActivityVideoKeyboardControl extends StatefulWidget {
  final VoidCallback onTogglePlayback;
  final VoidCallback onToggleMute;

  /// Null for a player with no captions to switch (uploaded video).
  final VoidCallback? onToggleCaptions;

  /// True when this player replaces a poster that was pressed from the
  /// keyboard: the pressed control is gone, so the player claims the focus it
  /// held.
  final bool autofocus;

  final Widget child;

  const ActivityVideoKeyboardControl({
    required this.onTogglePlayback,
    required this.onToggleMute,
    required this.child,
    this.onToggleCaptions,
    this.autofocus = false,
    super.key,
  });

  @override
  State<ActivityVideoKeyboardControl> createState() =>
      _ActivityVideoKeyboardControlState();
}

class _ActivityVideoKeyboardControlState
    extends State<ActivityVideoKeyboardControl> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'activity video');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightModeChanged);
    // Not Focus.autofocus: the pressed poster still holds the scope's focus
    // in the frame this mounts, and autofocus yields to a focused sibling.
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightModeChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onHighlightModeChanged(FocusHighlightMode _) {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final showRing = _focused && FocusRingTapTarget.highlightsEnabled;
    final captions = widget.onToggleCaptions;
    return Semantics(
      container: true,
      label: L10n.of(context).videoPlayer,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space):
              widget.onTogglePlayback,
          const SingleActivator(LogicalKeyboardKey.enter):
              widget.onTogglePlayback,
          const SingleActivator(LogicalKeyboardKey.keyK):
              widget.onTogglePlayback,
          const SingleActivator(LogicalKeyboardKey.keyM): widget.onToggleMute,
          const SingleActivator(LogicalKeyboardKey.keyC): ?captions,
        },
        child: Focus(
          focusNode: _focusNode,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: _RingBand(
            color: FocusRingTapTarget.twoToneOuter,
            show: showRing,
            child: _RingBand(
              color: FocusRingTapTarget.twoToneInner,
              show: showRing,
              child: ExcludeFocus(child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

/// One band of the two-tone ring. It always takes its width, so gaining focus
/// never resizes the player inside it.
class _RingBand extends StatelessWidget {
  final Color color;
  final bool show;
  final Widget child;

  const _RingBand({
    required this.color,
    required this.show,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(
        color: show ? color : Colors.transparent,
        width: FocusRingTapTarget.ringWidth,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(FocusRingTapTarget.ringWidth),
      child: child,
    ),
  );
}
