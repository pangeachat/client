import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';

/// The self-identified role, with onboarding's question as its label. Empty
/// for an account that has none.
class UserTypeDropdown extends StatelessWidget {
  final UserType? userType;
  final ValueChanged<UserType> onChanged;

  const UserTypeDropdown({
    super.key,
    required this.userType,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return DropdownButtonFormField<UserType>(
      decoration: InputDecoration(labelText: l10n.userTypeTitle),
      isExpanded: true,
      dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14.0),
      initialValue: userType,
      items: [
        for (final type in UserType.values)
          DropdownMenuItem(value: type, child: Text(type.title(l10n))),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}
