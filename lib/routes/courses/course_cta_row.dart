import 'package:flutter/material.dart';

/// One action in a [CourseCtaRow].
class CourseCtaAction {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  const CourseCtaAction({required this.label, this.icon, this.onPressed});
}

/// The course preview's pinned footer (#7826), kept visually in step with the
/// activity start page's mobile CTA row (activity_session_button_widget.dart):
/// one filled primary that stretches when everything fits, light chips after
/// it, and a horizontal scroll on overflow.
class CourseCtaRow extends StatelessWidget {
  final CourseCtaAction primary;
  final List<CourseCtaAction> secondary;

  const CourseCtaRow({
    required this.primary,
    this.secondary = const [],
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      _CourseCtaChip(action: primary, filled: true),
      for (final action in secondary) _CourseCtaChip(action: action),
    ];

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: IntrinsicWidth(
            child: Row(
              spacing: 8.0,
              children: [
                Expanded(child: chips.first),
                ...chips.skip(1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The stacked variant: full-width pills, every one primary — for steps whose
/// actions are equally valid ways forward, the same exception the activity
/// waiting room makes to the single-primary rule
/// (activity-start-page.instructions.md).
class CourseCtaColumn extends StatelessWidget {
  final List<CourseCtaAction> actions;

  const CourseCtaColumn({required this.actions, super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 8.0,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final action in actions)
          _CourseCtaChip(action: action, filled: true),
      ],
    );
  }
}

class _CourseCtaChip extends StatelessWidget {
  final CourseCtaAction action;
  final bool filled;

  const _CourseCtaChip({required this.action, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = ElevatedButton.styleFrom(
      backgroundColor: filled
          ? theme.colorScheme.primary
          : theme.colorScheme.primaryContainer,
      foregroundColor: filled
          ? theme.colorScheme.onPrimary
          : theme.colorScheme.onPrimaryContainer,
      elevation: 0.0,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
    );

    return SizedBox(
      height: 40.0,
      child: ElevatedButton(
        style: style,
        onPressed: action.onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (action.icon != null) ...[
              Icon(action.icon, size: 18.0),
              const SizedBox(width: 8.0),
            ],
            Text(action.label),
          ],
        ),
      ),
    );
  }
}
