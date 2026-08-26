import 'package:flutter/material.dart';

import 'package:fluffychat/widgets/matrix.dart';

/// Registers [child] as a tutorial spotlight target, so a step can point at it
/// by id. A null [targetId] is a plain pass-through, which is how a widget used
/// in several places lets only one of them claim the id — the id hands out a
/// GlobalKey, and two mounted claimants would collide.
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
