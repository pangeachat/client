import 'package:flutter/material.dart';

/// A course-page section's "see all" row: primary-colored label + chevron,
/// opening the section's full subpage within the card.
class CourseSectionLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const CourseSectionLink({
    required this.label,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(Icons.chevron_right, size: 18.0, color: color),
          ],
        ),
      ),
    );
  }
}
