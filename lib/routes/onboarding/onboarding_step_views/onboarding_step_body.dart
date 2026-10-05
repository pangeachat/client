import 'package:flutter/material.dart';

/// The named group holding a step's center content — the title and the
/// choices between the header and the forward button — labelled with the
/// step's visible title, so a screen reader entering it hears where it is and
/// one step up from it lands beside the header's Back button and progress bar
/// (accessibility.instructions.md § Focus after an in-place content swap).
///
/// A step that must scroll (a keyboard can cover it, #8598) keeps the group
/// and the scroll region as one node: a scrollable's own node cannot be named
/// and would be one more level to climb, so the `Scrollable` is kept out of
/// semantics and the group scrolls.
class OnboardingStepBody extends StatelessWidget {
  final String label;
  final bool scrollable;
  final Widget child;

  const OnboardingStepBody({
    super.key,
    required this.label,
    this.scrollable = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (scrollable) {
      return Semantics(
        container: true,
        explicitChildNodes: true,
        label: label,
        child: Scrollable(
          excludeFromSemantics: true,
          viewportBuilder: (context, offset) => ShrinkWrappingViewport(
            offset: offset,
            slivers: [SliverToBoxAdapter(child: child)],
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: label,
      child: child,
    );
  }
}
