import 'package:flutter/material.dart';

import 'package:dropdown_button2/dropdown_button2.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/dropdown_text_button.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';

class VoiceDropdown extends StatelessWidget {
  final String? value;
  final LanguageModel? language;
  final Function(String?) onChanged;

  const VoiceDropdown({
    super.key,
    this.value,
    this.language,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField2<String>(
      customButton:
          value != null ? CustomDropdownTextButton(text: value!) : null,
      menuItemStyleData: const MenuItemStyleData(
        padding: EdgeInsets.symmetric(
          vertical: 8.0,
          horizontal: 16.0,
        ),
      ),
      decoration: InputDecoration(
        labelText: L10n.of(context).voiceDropdownTitle,
      ),
      isExpanded: true,
      dropdownStyleData: DropdownStyleData(
        maxHeight: 250,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14.0),
        ),
      ),
      items: (language?.voices ?? <String>[]).map((voice) {
        return DropdownMenuItem(
          value: voice,
          child: Text(voice),
        );
      }).toList(),
      onChanged: onChanged,
      value: value,
    );
  }
}
