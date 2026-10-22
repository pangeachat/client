import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/bold_tonal_button.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';

/// The Mission card's main action, sitting on the card it opens (#9559): a
/// solid primary pill sized like the page's other buttons, so it leads by
/// colour (and its pulse) rather than by bulk. What it opens is the
/// highlighted first card of the row under it, named in [target] for the
/// tooltip and accessible name.
class MissionPlayButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;

  /// The activity it opens, or null when there is none to name.
  final String? target;

  /// A fixed width — the card it sits on — with the label scaled down to
  /// fit when a translation runs long; null hugs the label.
  final double? width;

  const MissionPlayButton({
    required this.onPressed,
    required this.label,
    this.target,
    this.width,
    super.key,
  });

  /// The page's button height — [BoldTonalButton]'s, which Practice and the
  /// section buttons use — so every button on the course page is one size.
  static const double height = 38.0;
  static const BorderRadius radius = BorderRadius.all(Radius.circular(999.0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onPressed != null;
    final fill = enabled ? scheme.primary : scheme.surfaceContainerHighest;
    final ink = enabled ? scheme.onPrimary : scheme.onSurfaceVariant;
    final target = this.target;
    final name = target == null
        ? label
        : L10n.of(context).missionPlayTarget(label, target);
    return Tooltip(
      message: target == null ? '' : name,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: name,
        // The pressable below is excluded, so the tap is published here.
        onTap: onPressed,
        child: ExcludeSemantics(
          child: PressableButton(
            borderRadius: radius,
            color: fill,
            buttonHeight: 4.0,
            onPressed: onPressed,
            builder: (context, depressed, shadowColor) => Container(
              height: height,
              width: width,
              // Only a fixed width centres the label; an alignment with no
              // width would stretch the pill to fill its row.
              alignment: width == null ? null : Alignment.center,
              padding: const EdgeInsetsDirectional.fromSTEB(
                10.0,
                0.0,
                14.0,
                0.0,
              ),
              decoration: BoxDecoration(
                color: depressed ? shadowColor : fill,
                borderRadius: radius,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4.0,
                  children: [
                    Icon(Icons.play_arrow_rounded, size: 22.0, color: ink),
                    Text(
                      label,
                      maxLines: 1,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
