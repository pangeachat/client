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
class TutorialTarget extends StatelessWidget {
  final String? targetId;
  final Widget child;

  const TutorialTarget({
    required this.targetId,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final targetId = this.targetId;
    if (targetId == null) return child;
    final target = MatrixState.pAnyState.layerLinkAndKey(targetId);
    return CompositedTransformTarget(
      link: target.link,
      key: target.key,
      child: child,
    );
  }
}
