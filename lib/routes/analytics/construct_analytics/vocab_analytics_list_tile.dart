import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_level_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/shrinkable_text.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';

class VocabAnalyticsListTile extends StatelessWidget {
  final void Function()? onTap;
  final void Function()? onLongPress;
  final ConstructIdentifier constructId;
  final ConstructLevelEnum level;
  final Color textColor;
  final bool selected;

  /// Whether to read live analytics state for the emoji — both the update
  /// stream and [ConstructIdentifier.userSetEmoji], which reaches the global
  /// [MatrixState]. False renders statically from [constructId] alone, needing
  /// no Matrix at all, which is what makes this tile widget-testable.
  final bool listen;

  /// Renders the deleted-vocab treatment: dimmed, and named as deleted in the
  /// tile's accessible name since dimming alone doesn't reach a screen reader.
  final bool blocked;

  const VocabAnalyticsListTile({
    super.key,
    required this.constructId,
    this.level = ConstructLevelEnum.seeds,
    required this.textColor,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.listen = true,
    this.blocked = false,
  });

  final double maxWidth = 100;
  final double padding = 8.0;

  @override
  Widget build(BuildContext context) {
    // The stream is hoisted above the whole tile (not just the emoji slot) so
    // the accessible name below can carry a live emoji change too (#8726).
    return StreamBuilder(
      // Read Matrix only when actually listening, so a tile pumped
      // with `listen: false` needs no Matrix ancestor and can be
      // widget-tested in a bare MaterialApp.
      stream: listen
          ? Matrix.of(context).analyticsDataService.updateDispatcher
                .lemmaUpdateStream(constructId)
          : null,
      builder: (context, snapshot) {
        final emoji =
            snapshot.data?.emojis?.firstOrNull ??
            (listen ? constructId.userSetEmoji : null);

        final Widget tile = HoverBuilder(
          builder: (context, hovered) => Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              onTap: onTap,
              onLongPress: onLongPress,
              child: Container(
                height: maxWidth,
                width: maxWidth,
                padding: EdgeInsets.all(padding),
                decoration: BoxDecoration(
                  color: hovered || selected
                      ? textColor.withAlpha(20)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      alignment: Alignment.center,
                      height: (maxWidth - padding * 2) * 0.6,
                      child: emoji != null
                          ? Text(emoji, style: const TextStyle(fontSize: 22))
                          : Text(
                              "-",
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: textColor.withAlpha(100),
                              ),
                            ),
                    ),
                    Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.only(top: 4),
                      height: (maxWidth - padding * 2) * 0.4,
                      child: ShrinkableText(
                        text: constructId.lemma,
                        maxWidth: maxWidth - padding * 2,
                        style: TextStyle(fontSize: 16, color: textColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // One semantics node for the whole tile, both branches: the inner
        // tree is excluded and tap/long-press re-exposed here so the row
        // stays reachable — Playwright resolves controls by role + name.
        //
        // Blocked: "<lemma>, deleted" once, rather than the lemma twice.
        // Dimming is the only visual marker. That would normally be
        // colour-alone, but every tile on the deleted-vocab page is blocked,
        // so a per-tile badge marks nothing the page title doesn't already
        // say — and the accessible name carries the state for anyone not
        // seeing the dimming.
        //
        // Unblocked (#8726): "<lemma>, <emoji if set>, <stage>". Without
        // this, the no-emoji placeholder dash was a text node — tiles
        // announced as "-, <lemma>" — and the word's growth stage reached
        // assistive tech nowhere.
        final l10n = L10n.of(context);
        return Semantics(
          label: blocked
              ? l10n.deletedWordLabel(constructId.lemma)
              : [constructId.lemma, ?emoji, level.displayName(l10n)].join(', '),
          button: true,
          container: true,
          onTap: onTap,
          onLongPress: onLongPress,
          child: ExcludeSemantics(
            child: blocked ? Opacity(opacity: 0.5, child: tile) : tile,
          ),
        );
      },
    );
  }
}
