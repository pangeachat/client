import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:fluffychat/widgets/theme_builder.dart';

class AppConfigDialog extends StatefulWidget {
  final List<AppConfigOverride> overrides;
  const AppConfigDialog({super.key, required this.overrides});

  @override
  State<AppConfigDialog> createState() => AppConfigDialogState();
}

class AppConfigDialogState extends State<AppConfigDialog> {
  AppConfigOverride? selectedOverride;

  @override
  void initState() {
    super.initState();
    selectedOverride = Environment.appConfigOverride;
  }

  void switchTheme(ThemeMode? newTheme) {
    if (newTheme == null) return;
    switch (newTheme) {
      case ThemeMode.light:
        ThemeController.of(context).setThemeMode(ThemeMode.light);
        break;
      case ThemeMode.dark:
        ThemeController.of(context).setThemeMode(ThemeMode.dark);
        break;
      case ThemeMode.system:
        ThemeController.of(context).setThemeMode(ThemeMode.system);
        break;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256),
        child: Text(
          L10n.of(context).addEnvironmentOverride,
          textAlign: TextAlign.center,
        ),
      ),
      content: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.all(16.0),
          constraints: const BoxConstraints(maxWidth: 256),
          child: SingleChildScrollView(
            child: RadioGroup<AppConfigOverride?>(
              groupValue: selectedOverride,
              onChanged: (override) {
                setState(() {
                  selectedOverride = override;
                });
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: SegmentedButton<ThemeMode>(
                      selected: {ThemeController.of(context).themeMode},
                      onSelectionChanged: (selected) =>
                          switchTheme(selected.single),
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text(L10n.of(context).lightTheme),
                          icon: const Icon(Icons.light_mode_outlined),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text(L10n.of(context).darkTheme),
                          icon: const Icon(Icons.dark_mode_outlined),
                        ),
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text(L10n.of(context).systemTheme),
                          icon: const Icon(Icons.auto_mode_outlined),
                        ),
                      ],
                    ),
                  ),
                  ...widget.overrides.map((override) {
                    return RadioListTile<AppConfigOverride?>.adaptive(
                      title: Text(
                        override.environment ?? L10n.of(context).unkDisplayName,
                      ),
                      value: override,
                    );
                  }).toList()..insert(
                    0,
                    RadioListTile<AppConfigOverride?>.adaptive(
                      title: Text(L10n.of(context).defaultOption),
                      value: null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        AdaptiveDialogAction(
          bigButtons: true,
          onPressed: () => Navigator.of(context).pop(selectedOverride),
          child: Text(L10n.of(context).submit),
        ),
        AdaptiveDialogAction(
          bigButtons: true,
          onPressed: Navigator.of(context).pop,
          child: Text(L10n.of(context).close),
        ),
      ],
    );
  }
}
