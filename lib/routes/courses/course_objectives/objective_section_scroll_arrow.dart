import 'package:flutter/material.dart';

enum ArrowDirection {
  back,
  forward;

  IconData get icon => switch (this) {
    ArrowDirection.back => Icons.chevron_left,
    ArrowDirection.forward => Icons.chevron_right,
  };
}

class ObjectiveSectionScrollArrow extends StatelessWidget {
  final ArrowDirection direction;
  final VoidCallback onTap;
  const ObjectiveSectionScrollArrow({
    super.key,
    required this.direction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(8.0),
      decoration: BoxDecoration(color: theme.colorScheme.surface),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Center(child: Icon(direction.icon)),
        ),
      ),
    );
  }
}
