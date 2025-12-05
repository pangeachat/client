import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:dropdown_button2/dropdown_button2.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/dropdown_text_button.dart';
import 'package:fluffychat/pangea/learning_settings/gender_enum.dart';

class GenderDropdown extends StatelessWidget {
  final GenderEnum initialGender;
  final Function(GenderEnum)? onChanged;
  final FormFieldValidator<Object>? validator;
  final bool enabled;
  final Color? backgroundColor;

  const GenderDropdown({
    super.key,
    this.initialGender = GenderEnum.unselected,
    this.onChanged,
    this.validator,
    this.enabled = true,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return DropdownButtonFormField2<GenderEnum>(
      customButton:
          CustomDropdownTextButton(text: initialGender.title(context)),
      menuItemStyleData: const MenuItemStyleData(
        padding: EdgeInsets.zero,
      ),
      decoration: InputDecoration(
        labelText: l10n.gender,
      ),
      isExpanded: true,
      dropdownStyleData: DropdownStyleData(
        maxHeight: kIsWeb ? 500 : null,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14.0),
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
        ),
      ),
      items: GenderEnum.values.map((GenderEnum genderOption) {
        return DropdownMenuItem(
          enabled: genderOption != GenderEnum.unselected,
          value: genderOption,
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 12,
            ),
            child: Text(
              genderOption.title(context),
              style: const TextStyle().copyWith(
                color: Theme.of(context).textTheme.bodyLarge!.color,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }).toList(),
      onChanged: enabled
          ? (value) {
              if (value != null) onChanged?.call(value);
            }
          : null,
      value: initialGender,
      validator: validator,
    );
  }
}
