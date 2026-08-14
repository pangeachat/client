import 'package:flutter/material.dart';

/// A course-page section title row — sections are divided by [Divider]s (the
/// settings-page convention), each headed by this: bold title, optional
/// [trailing] action (e.g. the Participants section's invite button).
class CourseSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const CourseSectionHeader({required this.title, this.trailing, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
