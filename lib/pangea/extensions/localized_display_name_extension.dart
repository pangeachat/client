import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';

/// The bot and support accounts have English profile display names
/// ("Pangea Bot", "Support"), which non-English speakers may not understand.
/// Returns the localized name for those accounts, or null for anyone else.
/// Wired into [MatrixLocals.displaynameOverride], which the matrix SDK applies
/// wherever it renders display names itself (state event texts, sender
/// prefixes, DM room names).
String? localizedPangeaUserName(String? userId, L10n l10n) {
  if (userId == BotName.byEnvironment) return l10n.botDisplayName;
  if (userId == Environment.supportUserId) return l10n.supportDisplayName;
  return null;
}

extension LocalizedUserDisplayname on User {
  /// [calcDisplayname], but with localized names for the bot and support
  /// accounts (via [MatrixLocals.displaynameOverride]).
  String localizedDisplayname(L10n l10n) =>
      calcDisplayname(i18n: MatrixLocals(l10n));
}
