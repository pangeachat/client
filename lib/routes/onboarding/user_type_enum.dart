import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/l10n/l10n.dart';

/// The value names are what [UserSettings.selfIdentifiedRole] stores in
/// account data, and outreach outside the app reads them there, so renaming
/// a value breaks those readers.
enum UserType {
  student,
  teacher;

  String title(L10n l10n) => switch (this) {
    UserType.teacher => l10n.teach,
    UserType.student => l10n.learn,
  };

  IconData get icon => switch (this) {
    UserType.teacher => Icons.school_outlined,
    UserType.student => Symbols.dictionary,
  };

  String selectedMessage(L10n l10n) => switch (this) {
    UserType.teacher => l10n.teachOptionSelected,
    UserType.student => l10n.learnOptionSelected,
  };
}
