import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';

/// The bot and support accounts have English profile display names
/// ("Pangea Bot", "Support"), which non-English speakers may not understand.
/// Returns the localized name for those accounts, or null for anyone else.
String? localizedPangeaUserName(String? userId, L10n l10n) {
  if (userId == BotName.byEnvironment) return l10n.botDisplayName;
  if (userId == Environment.supportUserId) return l10n.supportDisplayName;
  return null;
}

extension LocalizedUserDisplayname on User {
  /// [calcDisplayname], but with localized names for the bot and support
  /// accounts.
  String localizedDisplayname(L10n l10n) =>
      localizedPangeaUserName(id, l10n) ??
      calcDisplayname(i18n: MatrixLocals(l10n));
}

extension LocalizedEventBody on Event {
  /// The localized bot/support name for the sender prefix, when
  /// [Event.calcLocalizedBodyFallback] would prefix this event with the
  /// sender's profile name (mirrors the SDK's prefix guard).
  String? _senderPrefixOverride(L10n l10n) {
    if (type != EventTypes.Message ||
        !Event.textOnlyMessageTypes.contains(messageType) ||
        senderId == room.client.userID) {
      return null;
    }
    return localizedPangeaUserName(senderId, l10n);
  }

  /// [calcLocalizedBody], but with localized names for the bot and support
  /// accounts in the sender prefix.
  Future<String> localizedBody(
    L10n l10n, {
    bool withSenderNamePrefix = false,
    bool hideReply = false,
    bool hideEdit = false,
    bool plaintextBody = false,
    bool removeMarkdown = false,
  }) async {
    final prefix = withSenderNamePrefix ? _senderPrefixOverride(l10n) : null;
    final body = await calcLocalizedBody(
      MatrixLocals(l10n),
      withSenderNamePrefix: withSenderNamePrefix && prefix == null,
      hideReply: hideReply,
      hideEdit: hideEdit,
      plaintextBody: plaintextBody,
      removeMarkdown: removeMarkdown,
    );
    return prefix == null ? body : '$prefix: $body';
  }

  /// [calcLocalizedBodyFallback], but with localized names for the bot and
  /// support accounts in the sender prefix.
  String localizedBodyFallback(
    L10n l10n, {
    bool withSenderNamePrefix = false,
    bool hideReply = false,
    bool hideEdit = false,
    bool plaintextBody = false,
    bool removeMarkdown = false,
  }) {
    final prefix = withSenderNamePrefix ? _senderPrefixOverride(l10n) : null;
    final body = calcLocalizedBodyFallback(
      MatrixLocals(l10n),
      withSenderNamePrefix: withSenderNamePrefix && prefix == null,
      hideReply: hideReply,
      hideEdit: hideEdit,
      plaintextBody: plaintextBody,
      removeMarkdown: removeMarkdown,
    );
    return prefix == null ? body : '$prefix: $body';
  }
}

extension LocalizedRoomDisplayname on Room {
  /// [getLocalizedDisplayname], but with localized names for bot and support
  /// DMs, whose display name is the other party's profile name.
  String localizedDisplayname(L10n l10n) {
    final override = name.isEmpty
        ? localizedPangeaUserName(directChatMatrixID, l10n)
        : null;
    if (override != null) {
      if (isAbandonedDMRoom || membership == Membership.leave) {
        return MatrixLocals(l10n).wasDirectChatDisplayName(override);
      }
      return override;
    }
    return getLocalizedDisplayname(MatrixLocals(l10n));
  }
}
