import 'package:flutter/material.dart';

import 'package:fluffychat/widgets/matrix.dart';

/// Registers [child] as a tutorial spotlight target, so a step can point at it
/// by id.
///
/// **One mounted claimant per id, ever.** An id resolves to a single
/// `LabeledGlobalKey` in the overlay registry, and a GlobalKey may only be
/// attached to one mounted widget at a time — two claimants throw. So a widget
/// that renders in more than one place takes its id as a nullable parameter and
/// a null [targetId] is a plain pass-through: the mount site the tutorial
/// actually points at passes the id, every other one passes nothing. Everywhere
/// an id is declared or claimed, the comment says *which* mount site claims it;
/// the reason it has to be only one is here.
class TutorialTarget extends StatefulWidget {
  final String? targetId;

  /// Fires once, post-frame, when this target mounts while claiming an id
  /// (and again if a null id later becomes one). A trigger that gates on "is
  /// the target on screen" listens here, because the target can arrive after
  /// every other signal has already fired — a mobile sheet finishing its
  /// expand animation, a list landing — and a trigger keeps asking
  /// (tutorials.instructions.md).
  final VoidCallback? onMounted;

  final Widget child;

  const TutorialTarget({
    required this.targetId,
    required this.child,
    this.onMounted,
    super.key,
  });

  @override
  State<TutorialTarget> createState() => _TutorialTargetState();
}

class _TutorialTargetState extends State<TutorialTarget> {
  @override
  void initState() {
    super.initState();
    _notifyIfClaiming();
  }

  @override
  void didUpdateWidget(covariant TutorialTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetId == null && widget.targetId != null) {
      _notifyIfClaiming();
    }
  }

  void _notifyIfClaiming() {
    final onMounted = widget.onMounted;
    if (widget.targetId == null || onMounted == null) return;
    // Post-frame, so the render box exists by the time the listener checks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) onMounted();
    });
  }

  @override
  Widget build(BuildContext context) {
    final targetId = widget.targetId;
    if (targetId == null) return widget.child;
    final target = MatrixState.pAnyState.layerLinkAndKey(targetId);
    return CompositedTransformTarget(
      link: target.link,
      key: target.key,
      child: widget.child,
    );
  }
}
