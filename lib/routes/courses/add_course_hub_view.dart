import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The "Add new course" hub (world_v2): a compact card that floats at the top
/// of the left column over the persistent map — the rail `+` opens it. Three
/// entry points, each a panel that keeps the map visible: make your own,
/// join a private course by code, or browse public ones.
///
/// Background is transparent so the map shows around and below the card; only
/// the card itself is opaque.
class AddCourseHubView extends StatelessWidget {
  const AddCourseHubView({super.key});

  @override
  Widget build(BuildContext context) {
    // Float the card at the top-left over the full-bleed map. Everything
    // outside the card is left empty so taps/drags fall through to the map —
    // only the card itself is interactive.
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360.0),
            child: const _AddCourseCard(),
          ),
        ),
      ),
    );
  }
}

class _AddCourseCard extends StatelessWidget {
  const _AddCourseCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: theme.colorScheme.primary),
        boxShadow: const [BoxShadow(blurRadius: 16.0, color: Colors.black26)],
      ),
      padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 12.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const SizedBox(width: 40.0),
              Expanded(
                child: Text(
                  l10n.addNewCourse,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.close,
                onPressed: () => context.go(PRoutes.world),
              ),
            ],
          ),
          const SizedBox(height: 4.0),
          _HubButton(
            icon: Icons.auto_stories_outlined,
            label: l10n.addCourseStartMyOwn,
            onTap: () => context.go('${PRoutes.courses}/own?showAll=true'),
          ),
          const SizedBox(height: 8.0),
          _HubButton(
            icon: Icons.vpn_key_outlined,
            label: l10n.addCourseEnterCode,
            onTap: () => context.go('${PRoutes.courses}/private'),
          ),
          const SizedBox(height: 8.0),
          _HubButton(
            icon: Icons.travel_explore_outlined,
            label: l10n.addCourseBrowsePublic,
            onTap: () => context.go('${PRoutes.courses}/browse'),
          ),
        ],
      ),
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
