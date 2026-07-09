import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The three add-course options — Start my own / Enter code for a private
/// course / Browse public courses — as a standalone, chromeless block. Lives at
/// the bottom of the Courses panel (below the joined-course list) and is also
/// the body of the legacy add-course hub. Each option is a token-native
/// `setSection` to the `addcourse` left panel at its step, replacing the open
/// left panels (a focused flow, no chat floating over it). See
/// routing.instructions.md.
class AddCourseOptions extends StatelessWidget {
  const AddCourseOptions({super.key});

  void _goToStep(BuildContext context, AddCourseSubpageEnum step) => context.go(
    WorkspaceNav.openAddCoursePage(GoRouterState.of(context).uri, step),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HubButton(
          icon: Icons.auto_stories_outlined,
          label: l10n.addCourseStartMyOwn,
          // No showAll: the plan list defaults to the user's target language
          // (the filter still lets them widen to all). showAll=true here would
          // suppress that default and list every language (#7081).
          onTap: () => _goToStep(context, AddCourseSubpageEnum.own),
        ),
        const SizedBox(height: 8.0),
        _HubButton(
          icon: Icons.vpn_key_outlined,
          label: l10n.addCourseEnterCode,
          onTap: () => _goToStep(context, AddCourseSubpageEnum.private),
        ),
        const SizedBox(height: 8.0),
        _HubButton(
          icon: Icons.travel_explore_outlined,
          label: l10n.addCourseBrowsePublic,
          onTap: () => _goToStep(context, AddCourseSubpageEnum.browse),
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
