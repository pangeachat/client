import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';

class MissionPlayButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String? label;
  final String? detail;

  const MissionPlayButton({
    required this.onPressed,
    this.label,
    this.detail,
    super.key,
  });

  static const BorderRadius _radius = BorderRadius.all(Radius.circular(18.0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onPressed != null;
    final fill = enabled ? scheme.primary : scheme.surfaceContainerHighest;
    final ink = enabled ? scheme.onPrimary : scheme.onSurfaceVariant;
    final label = this.label ?? L10n.of(context).playMission;
    final detail = this.detail;
    return Semantics(
      button: true,
      enabled: enabled,
      label: detail == null ? label : '$label: $detail',
      // The pressable below is excluded, so the tap is published here.
      onTap: onPressed,
      child: ExcludeSemantics(
        child: PressableButton(
          borderRadius: _radius,
          color: fill,
          buttonHeight: 5.0,
          onPressed: onPressed,
          builder: (context, depressed, shadowColor) => Container(
            constraints: const BoxConstraints(minHeight: 48.0),
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 6.0,
            ),
            decoration: BoxDecoration(
              color: depressed ? shadowColor : fill,
              borderRadius: _radius,
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8.0,
                  children: [
                    Icon(Icons.play_arrow_rounded, size: 26.0, color: ink),
                    Text(
                      label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (detail != null)
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
