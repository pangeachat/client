import 'package:flutter/material.dart';

/// Makes an overlay entry modal to the keyboard (#9191). An [OverlayEntry] is
/// no route, so it gets none of what [ModalRoute] gives a dialog: its controls
/// land in the focus scope above the [Overlay], where Tab from the page never
/// reaches them, and Tab keeps walking the page behind the scrim. This gives
/// the entry a scope of its own, so Tab cycles through its controls; maps
/// Escape ([DismissIntent]) to [onDismiss]; and on close hands focus back to
/// the node that held it when the entry opened.
class OverlayKeyboardModal extends StatefulWidget {
  /// What Escape does. Null means nothing: the key is still consumed here, so
  /// it never reaches whatever the page behind the overlay would do with it.
  /// A tutorial card with no way out (the greeting, a one-step run) passes
  /// null rather than skipping a sequence the learner has not been offered
  /// a way out of.
  final VoidCallback? onDismiss;
  final Widget child;

  const OverlayKeyboardModal({
    required this.onDismiss,
    required this.child,
    super.key,
  });

  @override
  State<OverlayKeyboardModal> createState() => _OverlayKeyboardModalState();
}

class _OverlayKeyboardModalState extends State<OverlayKeyboardModal> {
  final FocusScopeNode _scopeNode = FocusScopeNode(
    debugLabel: 'OverlayKeyboardModal',
  );
  FocusNode? _focusBeforeOpen;

  @override
  void initState() {
    super.initState();
    _focusBeforeOpen = FocusManager.instance.primaryFocus;
    // Not `autofocus`: it is a no-op while the enclosing scope already has a
    // focused child, and it always has one when a focused control opened the
    // overlay. Focus lands on the scope, not a control, so no ring shows
    // until the learner presses Tab.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scopeNode.requestFocus();
    });
  }

  /// Hands focus back to whatever held it when the overlay opened, unless
  /// something else claimed focus on the way out: editing a message closes
  /// the toolbar and focuses the composer, and that claim stands.
  void _handFocusBack() {
    final focusBeforeOpen = _focusBeforeOpen;
    if (_scopeNode.hasFocus && focusBeforeOpen?.context != null) {
      focusBeforeOpen!.requestFocus();
    }
  }

  /// Escape hands focus back before the entry goes rather than after, so the
  /// move reaches the browser in the same semantics update that removes the
  /// overlay. A frame later, the web engine has already parked focus on the
  /// page's first control, and a screen reader follows it there.
  void _dismiss() {
    final onDismiss = widget.onDismiss;
    if (onDismiss == null) return;
    _handFocusBack();
    onDismiss();
  }

  @override
  void deactivate() {
    // Every other way of closing. Children detach before dispose() runs, so
    // this is the last point where the scope still knows it holds focus.
    _handFocusBack();
    super.deactivate();
  }

  @override
  void dispose() {
    _scopeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) => _dismiss(),
        ),
        // Tab and Shift+Tab are always consumed here. The default focus
        // actions report the key unhandled when there is nowhere to move —
        // a card with one control — and on web an unhandled Tab falls
        // through to the browser, whose native Tab parks focus on the host
        // element outside the scope (#9050).
        NextFocusIntent: CallbackAction<NextFocusIntent>(
          onInvoke: (_) => FocusManager.instance.primaryFocus?.nextFocus(),
        ),
        PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
          onInvoke: (_) => FocusManager.instance.primaryFocus?.previousFocus(),
        ),
      },
      child: FocusScope(node: _scopeNode, child: widget.child),
    );
  }
}
