import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';

import 'package:fluffychat/pangea/chat_settings/utils/language_level_copy.dart';
import 'package:fluffychat/pangea/common/widgets/dropdown_text_button.dart';
import 'package:fluffychat/pangea/learning_settings/enums/language_level_type_enum.dart';

class LanguageLevelDropdown extends StatelessWidget {
  final LanguageLevelTypeEnum? initialLevel;
  final Function(LanguageLevelTypeEnum)? onChanged;
  final FormFieldValidator<Object>? validator;
  final bool enabled;
  final Color? backgroundColor;

  const LanguageLevelDropdown({
    super.key,
    this.initialLevel = LanguageLevelTypeEnum.a1,
    this.onChanged,
    this.validator,
    this.enabled = true,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    final levels = [
      {'label': l10n.languageLevelPreA1, 'desc': l10n.languageLevelPreA1Desc},
      {'label': l10n.languageLevelA1, 'desc': l10n.languageLevelA1Desc},
      {'label': l10n.languageLevelA2, 'desc': l10n.languageLevelA2Desc},
      {'label': l10n.languageLevelB1, 'desc': l10n.languageLevelB1Desc},
      {'label': l10n.languageLevelB2, 'desc': l10n.languageLevelB2Desc},
      {'label': l10n.languageLevelC1, 'desc': l10n.languageLevelC1Desc},
      {'label': l10n.languageLevelC2, 'desc': l10n.languageLevelC2Desc},
    ];

    return SingleChildScrollView(
      child: DropdownButtonFormField2<LanguageLevelTypeEnum>(
        customButton: initialLevel != null &&
                LanguageLevelTypeEnum.values.contains(initialLevel)
            ? CustomDropdownTextButton(
                text: LanguageLevelTextPicker.languageLevelText(
                  context,
                  initialLevel!,
                ),
              )
            : null,
        menuItemStyleData: const MenuItemStyleData(
          padding: EdgeInsets.zero, // Remove default padding
          height: 75,
        ),
        decoration: InputDecoration(
          labelText: l10n.cefrLevelLabel,
        ),
        isExpanded: true,
        dropdownStyleData: DropdownStyleData(
          maxHeight: kIsWeb ? 500 : null,
          decoration: BoxDecoration(
            color: backgroundColor ??
                Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14.0),
          ),
        ),
        items: LanguageLevelTypeEnum.values
            .map((LanguageLevelTypeEnum levelOption) {
          final level = levels.firstWhere(
            (level) =>
                level['label'] ==
                LanguageLevelTextPicker.languageLevelText(
                  context,
                  levelOption,
                ),
            orElse: () => {'label': '', 'desc': ''},
          );
          return DropdownMenuItem(
            value: levelOption,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Text(
                    level['label']!,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Text(
                    level['desc']!,
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey
                          : Colors.black,
                      fontSize: 14,
                    ),
                    maxLines: null,
                    overflow: TextOverflow.visible,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: enabled
            ? (value) => onChanged?.call(value as LanguageLevelTypeEnum)
            : null,
        value: initialLevel,
        validator: validator,
      ),
    );
  }
}
