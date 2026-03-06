import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/learning_settings/language_level_type_enum.dart';

class LanguageLevelDropdown extends StatelessWidget {
  final LanguageLevelTypeEnum? initialLevel;
  final Function(LanguageLevelTypeEnum)? onChanged;
  final bool enabled;

  const LanguageLevelDropdown({
    super.key,
    this.initialLevel = LanguageLevelTypeEnum.a1,
    this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return ButtonTheme(
      alignedDropdown: true,
      child: DropdownButtonFormField<LanguageLevelTypeEnum>(
        itemHeight: null,
        decoration: InputDecoration(labelText: l10n.cefrLevelLabel),
        selectedItemBuilder: (context) => LanguageLevelTypeEnum.values
            .map((levelOption) => Text(levelOption.title(context)))
            .toList(),
        isExpanded: true,
        dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14.0),
        onChanged: enabled
            ? (value) {
                if (value != null) onChanged?.call(value);
              }
            : null,
        initialValue: initialLevel,
        items: LanguageLevelTypeEnum.values.map((
          LanguageLevelTypeEnum levelOption,
        ) {
          return DropdownMenuItem(
            value: levelOption,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(levelOption.title(context)),
                  Flexible(
                    child: Text(
                      levelOption.description(context),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
