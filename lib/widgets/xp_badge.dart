import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/completed_stamp.dart';

/// The learner's XP from something that has no finish (#9647): the XP tab of
/// the completed stamp ([CompletedStamp]) — gold text on the same see-through
/// pill, sized the same for a card this [width] — without the coin.
class XpBadge extends StatelessWidget {
  final int xp;
  final double width;

  const XpBadge({required this.xp, required this.width, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = (width / 8).clamp(14.0, 18.0);
    final fontSize = (size * 0.75).clamp(10.0, 12.0);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(6.0, 2.0, 7.0, 2.0),
      decoration: BoxDecoration(
        color: CompletedStamp.scrimOf(theme),
        borderRadius: BorderRadius.circular(999.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 3.0,
        children: [
          Icon(
            Icons.auto_awesome,
            size: fontSize + 2.0,
            color: theme.pangea.gold,
          ),
          Text(
            L10n.of(context).xpAmount(xp),
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: theme.pangea.gold,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
