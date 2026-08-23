import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// The map's "you asked for a level we have nothing at" notice: the Level pill
/// still reads the level the learner chose, so the substitution has to be said
/// out loud rather than silently performed (world-map.instructions.md, "Empty
/// levels fall back to the nearest one with content").
///
/// Purely informational — no lever. The substitution has already put content on
/// the map, and the pill row's own reset is the way back out; a second button
/// here would only offer to undo something that is helping.
///
/// Presentational, like [WorldMapEmptyViewCard]: the hosts decide when it
/// mounts. It renders nothing unless a fallback is actually in force, and it
/// yields to the empty-view card, which diagnoses a map with nothing on it at
/// all and is always the more urgent message.
class WorldMapLevelFallbackNotice extends StatelessWidget {
  /// The level the learner picked on the Level pill.
  final LanguageLevelTypeEnum? selected;

  /// The level standing in for it ([WorldMapFilter.cefrFallback]); null when the
  /// choice is being honoured exactly, which draws nothing.
  final LanguageLevelTypeEnum? fallback;

  const WorldMapLevelFallbackNotice({
    super.key,
    required this.selected,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = selected;
    final shown = fallback;
    if (chosen == null || shown == null) return const SizedBox.shrink();

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8.0,
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            Flexible(
              child: Semantics(
                container: true,
                child: Text(
                  L10n.of(
                    context,
                  ).mapLevelFallbackNotice(chosen.shortLabel, shown.shortLabel),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
