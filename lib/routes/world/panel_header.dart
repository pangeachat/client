import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';

/// The header row shared by both workspace panel columns: a [leading]
/// close/back control at the start, a small gap, then the panel [title].
///
/// The two columns ([WorkspaceLeftPanel] / [WorkspaceRightPanel]) keep their own
/// close LOGIC — they rewrite different `?left=`/`?right=` lists and decide `←`
/// vs `X` separately — but the header CHROME (padding, control-to-title gap, and
/// the title's single-line ellipsised titleMedium/w600 styling) is identical, so
/// it lives here once and can't drift between columns. The surrounding
/// floating-card surface is [PanelCard]. See `routing.instructions.md`.
class PanelHeader extends StatelessWidget {
  /// The leading control — an `IconButton`/`BackButton` the column built from its
  /// own close affordance. Placed at the row's start.
  final Widget leading;

  /// The panel title shown beside [leading]; empty for panels whose body renders
  /// its own title.
  final String title;

  final Widget? trailing;

  const PanelHeader({
    super.key,
    required this.leading,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 8.0,
        vertical: FluffyThemes.isColumnMode(context) ? 16.0 : 8.0,
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 8),
          Expanded(
            child: ExcludeSemantics(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FluffyThemes.isColumnMode(context)
                    ? Theme.of(context).textTheme.titleLarge
                    : Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
