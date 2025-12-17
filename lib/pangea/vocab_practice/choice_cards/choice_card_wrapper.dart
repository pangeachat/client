import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';

/// Wrapper that provides the CompositedTransformTarget for all choice cards, allows for XP sparkle on all choices
class ChoiceCardWrapper extends StatelessWidget {
  final String choiceId;
  final Widget child;

  const ChoiceCardWrapper({
    required this.choiceId,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final transformTargetId =
        'vocab-choice-card-${choiceId.replaceAll(' ', '_')}';

    return CompositedTransformTarget(
      link: MatrixState.pAnyState.layerLinkAndKey(transformTargetId).link,
      child: child,
    );
  }
}
