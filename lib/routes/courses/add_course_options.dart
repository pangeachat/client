import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The three add-course steps, in display order, each with its icon. One list
/// keeps the two presentations in lockstep: the full-width buttons
/// ([AddCourseOptions], the Courses panel's empty state) and the compact header
/// icons ([AddCourseHeaderActions], shown once the learner is in a course).
const List<({IconData icon, AddCourseSubpageEnum step})> _addCourseActions = [
  (icon: Icons.auto_stories_outlined, step: AddCourseSubpageEnum.own),
  (icon: Icons.vpn_key_outlined, step: AddCourseSubpageEnum.private),
  (icon: Icons.travel_explore_outlined, step: AddCourseSubpageEnum.browse),
];

String _addCourseLabel(L10n l10n, AddCourseSubpageEnum step) => switch (step) {
  AddCourseSubpageEnum.own => l10n.addCourseStartMyOwn,
  AddCourseSubpageEnum.private => l10n.addCourseEnterCode,
  AddCourseSubpageEnum.browse => l10n.addCourseBrowsePublic,
};

/// Each option is a token-native `setSection` to the `addcourse` left panel at
/// its step (the plan list defaults to the user's target language; no showAll).
void _goToStep(BuildContext context, AddCourseSubpageEnum step) => context.go(
  WorkspaceNav.openAddCoursePage(GoRouterState.of(context).uri, step),
);

/// The three add-course options — Start my own / Enter code for a private
/// course / Browse public courses — as full-width tonal buttons. This is the
/// **empty state** of the Courses panel (shown when the learner is in no
/// courses yet); once they have a course the same three actions ride the panel
/// header as compact icons ([AddCourseHeaderActions]). See
/// routing.instructions.md.
class AddCourseOptions extends StatelessWidget {
  const AddCourseOptions({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, action) in _addCourseActions.indexed) ...[
          if (index > 0) const SizedBox(height: 8.0),
          _HubButton(
            icon: action.icon,
            label: _addCourseLabel(l10n, action.step),
            onTap: () => _goToStep(context, action.step),
          ),
        ],
      ],
    );
  }
}

/// The three add-course actions as compact icon-buttons, for the Courses panel
/// header once the learner has at least one course — so the joined-course list
/// keeps the vertical space three full-width buttons would otherwise take.
class AddCourseHeaderActions extends StatelessWidget {
  const AddCourseHeaderActions({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in _addCourseActions)
          IconButton(
            tooltip: _addCourseLabel(l10n, action.step),
            icon: Icon(action.icon),
            onPressed: () => _goToStep(context, action.step),
          ),
      ],
    );
  }
}

class _HubButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HubButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: onTap,
        icon: Icon(icon, size: 20.0),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          padding: const EdgeInsets.symmetric(vertical: 14.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.0),
          ),
        ),
      ),
    );
  }
}
