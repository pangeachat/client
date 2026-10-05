import 'dart:async';

import 'package:flutter/material.dart';

/// The named group that is a whole onboarding step — header, center content
/// and forward button — and what the screen reader lands on when a step is
/// swapped in, announced by the step's page label
/// (accessibility.instructions.md § Focus after an in-place content swap).
///
/// Left alone, a swap strands the screen reader on the header's Back button:
/// the control that was just pressed disappears, so the web engine parks DOM
/// focus on the view host and the framework hands focus to the last surviving
/// control it remembers — Back, once it has ever been pressed (#7582). The
/// claim is one discrete event a beat after the swap, past the engine's
/// host-focus hop, which VoiceOver otherwise latches onto (#8769).
class OnboardingPageGroup extends StatefulWidget {
  /// Identity of the step shown; a change re-claims focus for the new step.
  final Object? stepKey;
  final String label;
  final Widget child;

  const OnboardingPageGroup({
    super.key,
    this.stepKey,
    required this.label,
    required this.child,
  });

  @override
  State<OnboardingPageGroup> createState() => _OnboardingPageGroupState();
}

class _OnboardingPageGroupState extends State<OnboardingPageGroup> {
  // Not a Tab stop: keyboard users go straight to the controls inside.
  final FocusNode _node = FocusNode(
    debugLabel: 'OnboardingPageGroup',
    skipTraversal: true,
  );
  Timer? _claimFocus;

  @override
  void initState() {
    super.initState();
    _node.addListener(_rebuild);
    _arm();
  }

  @override
  void didUpdateWidget(OnboardingPageGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stepKey != widget.stepKey) _arm();
  }

  void _arm() {
    _claimFocus?.cancel();
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
    // `explicitChildNodes` keeps the header, content and forward button as
    // their own nodes; without it this label absorbs the first mergeable
    // descendant — BotFace's loading spinner role — and stops being a group
    // (#8175).
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
