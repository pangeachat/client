import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The gold "Invited" pill worn by anything the learner has been invited to but
/// hasn't joined yet — a course tile in the Courses hub, a room row in the chat
/// list. Gold rather than error-colored, and an envelope rather than a warning
/// glyph: an invitation is an opportunity, not a problem (#7636). It is the
/// text half of the same state marker `InvitedCourseBadge` puts on the avatar.
///
/// One widget for every surface so the pill can't drift between them, or from
/// the badge beside it. The fill is [AppConfig.goldByTheme] used as given —
/// washing it with a translucent surface first dragged the dark theme's gold
/// toward the near-black surface and left it muddy and visibly off the badge on
/// the same tile (#8109).
class InvitedChip extends StatelessWidget {
  final double fontSize;
  final double iconSize;

  const InvitedChip({super.key, this.fontSize = 12.0, this.iconSize = 12.0});

  @override
  Widget build(BuildContext context) {
    final foregroundColor = AppConfig.onGoldByTheme(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppConfig.goldByTheme(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        spacing: 4.0,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mail, size: iconSize, color: foregroundColor),
          Text(
            L10n.of(context).invited,
            style: TextStyle(fontSize: fontSize, color: foregroundColor),
          ),
        ],
      ),
    );
  }
}
