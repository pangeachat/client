import 'package:fluffychat/l10n/l10n.dart';

/// The value names are what [UserSettings.selfIdentifiedRole] stores in
/// account data, and outreach outside the app reads them there, so renaming
/// a value breaks those readers.
enum UserType {
  student,
  teacher;

  String selectedMessage(L10n l10n) => switch (this) {
    UserType.teacher => l10n.teachOptionSelected,
    UserType.student => l10n.learnOptionSelected,
  };
}
