import 'package:flutter/material.dart';

/// The door-and-arrow mark on the class-code dialog and notice.
class JoinCourseBadge extends StatelessWidget {
  final double size;

  const JoinCourseBadge({required this.size, super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.login,
          size: size / 2,
          color: colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
