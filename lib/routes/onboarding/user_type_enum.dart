import 'package:fluffychat/l10n/l10n.dart';

enum UserType {
  student,
  teacher;

  String selectedMessage(L10n l10n) => switch (this) {
    UserType.teacher => l10n.teachOptionSelected,
    UserType.student => l10n.learnOptionSelected,
  };
}
