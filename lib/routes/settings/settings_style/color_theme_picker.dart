import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/color_value.dart';
import 'settings_style.dart';

/// The accent-colour swatches on settings > change your style.
///
/// Sized to its content: the grid renders every swatch and leaves scrolling to
/// the page it sits in, so it never scrolls on its own (#7758).
class ColorThemePicker extends StatelessWidget {
  /// The platform's dynamic colour, or null where there is none (e.g. web).
  /// When null, the "system theme" swatch is dropped from the list.
  final Color? systemColor;
  final Color? currentColor;
  final void Function(Color?) onColorSelected;

  const ColorThemePicker({
    required this.systemColor,
    required this.currentColor,
    required this.onColorSelected,
    super.key,
  });

  static const double colorPickerSize = 32.0;

  @override
  Widget build(BuildContext context) {
    final colors = List<Color?>.from(SettingsStyleController.customColors);
    if (systemColor == null) {
      colors.remove(null);
    }

    return Semantics(
      label: L10n.of(context).colorListLabel,
      container: true,
      child: GridView.builder(
        shrinkWrap: true,
        // The grid sizes to its content inside the page's scroll view, so it
        // has nothing of its own to scroll; left scrollable, it only swallowed
        // drags that should have scrolled the page.
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 64,
        ),
        itemCount: colors.length,
        itemBuilder: (context, i) {
          final color = colors[i];
          return Padding(
            padding: const EdgeInsets.all(12.0),
            child: Tooltip(
              message: color == null
                  ? L10n.of(context).systemTheme
                  : '#${color.hexValue.toRadixString(16).toUpperCase()}',
              child: InkWell(
                borderRadius: BorderRadius.circular(colorPickerSize),
                onTap: () => onColorSelected(color),
                child: Material(
                  color: color ?? systemColor,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(colorPickerSize),
                  child: SizedBox(
                    width: colorPickerSize,
                    height: colorPickerSize,
                    child:
                        (currentColor == color ||
                            // #7176: on the default (null) colour the system
                            // swatch carries the selection, but where there is
                            // no system colour (web) that swatch is removed and
                            // the app falls back to its default colour — mark
                            // that swatch selected so a theme always reads as
                            // chosen.
                            (currentColor == null &&
                                systemColor == null &&
                                color == AppConfig.chatColor))
                        ? Center(
                            child: Icon(
                              Icons.check,
                              size: 16,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
