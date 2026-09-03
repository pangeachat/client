import 'dart:async';

import 'package:flutter/material.dart';

/// The group holding a step's center content — everything between the app bar
/// and the forward button — and where focus lands when a step is swapped in
/// (accessibility.instructions.md § Focus after an in-place content swap).
///
/// Left alone, a swap strands the screen reader on the app bar's Back button:
/// the control that was just pressed disappears, so the web engine parks DOM
/// focus on the view host and the framework hands focus to the last surviving
/// control it remembers — Back, once it has ever been pressed (#7582). The
/// claim is one discrete event a beat after mount, past the engine's
/// host-focus hop, which VoiceOver otherwise latches onto (#8769).
class OnboardingStepBody extends StatefulWidget {
  final String label;
  final Widget child;

  const OnboardingStepBody({
    super.key,
    required this.label,
    required this.child,
  });

  @override
  State<OnboardingStepBody> createState() => _OnboardingStepBodyState();
}

class _OnboardingStepBodyState extends State<OnboardingStepBody> {
  // Not a Tab stop: keyboard users go straight to the controls inside.
  final FocusNode _node = FocusNode(
    debugLabel: 'OnboardingStepBody',
    skipTraversal: true,
  );
  Timer? _claimFocus;

  @override
  void initState() {
    super.initState();
    _node.addListener(_rebuild);
    _claimFocus = Timer(const Duration(milliseconds: 300), _node.requestFocus);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _claimFocus?.cancel();
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.label,
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
