import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/notifications/communication_preferences.dart';
import 'package:fluffychat/features/notifications/email_pusher_changes.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

class EmailNotificationsStatus {
  final bool enabled;
  final bool canEnable;

  const EmailNotificationsStatus({
    required this.enabled,
    required this.canEnable,
  });
}

extension NotificationsExtension on Client {
  static const _legacyEmailSettingKey = 'enable_email_notifs';

  Future<EmailNotificationsStatus> get emailNotificationsStatus async {
    try {
      final addresses = await _emailAddresses();
      final preferences = await _fetchCommunicationPreferences();
      return EmailNotificationsStatus(
        enabled: addresses.isNotEmpty && !preferences.refusesMissedMessageEmail,
        canEnable: addresses.isNotEmpty,
      );
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'client_user_id': userID});
      rethrow;
    }
  }

  Future<void> setMissedMessageEmailsEnabled(bool enabled) async {
    await _recordMissedMessageEmailChoice(enabled);
    await _applyEmailPushers(enabled);
  }

  /// Makes the email pushers follow the stored choice, which the emailed
  /// unsubscribe link and other devices change without this client.
  Future<void> syncEmailPushers() async {
    final preferences = await _fetchCommunicationPreferences();
    await _applyEmailPushers(!preferences.refusesMissedMessageEmail);
  }

  /// Carries an opt-out made before the shared store existed into it, then
  /// clears the old event so the carry happens once.
  Future<void> migrateLegacyEmailSetting() async {
    final legacy =
        accountData[PangeaEventTypes.legacyNotificationSettings]?.content;
    if (legacy == null || legacy.isEmpty) return;
    if (legacy[_legacyEmailSettingKey] == false) {
      await _recordMissedMessageEmailChoice(false);
    }
    await setAccountData(
      userID!,
      PangeaEventTypes.legacyNotificationSettings,
      {},
    );
  }

  Future<void> _recordMissedMessageEmailChoice(bool enabled) async {
    final current = await _fetchCommunicationPreferences();
    if (current.refusesMissedMessageEmail != enabled) return;
    await setAccountData(
      userID!,
      PangeaEventTypes.communicationPreferences,
      current.withMissedMessageEmailRefused(!enabled, DateTime.now()).toJson(),
    );
  }

  Future<void> _applyEmailPushers(bool emailsEnabled) async {
    final changes = EmailPusherChanges.toMatch(
      emailsEnabled: emailsEnabled,
      addresses: await _emailAddresses(),
      pushers: await getPushers() ?? [],
    );
    for (final address in changes.addressesToAdd) {
      await postPusher(EmailPusherChanges.pusherFor(address));
    }
    for (final pusher in changes.pushersToRemove) {
      await deletePusher(pusher);
    }
  }

  Future<Set<String>> _emailAddresses() async =>
      ((await getAccount3PIDs()) ?? [])
          .where((p) => p.medium == ThirdPartyIdentifierMedium.email)
          .map((p) => p.address)
          .toSet();

  /// Read from the server, not the synced copy, so a write merges onto the
  /// latest refusals.
  Future<CommunicationPreferences> _fetchCommunicationPreferences() async {
    try {
      return CommunicationPreferences.fromJson(
        await getAccountData(
          userID!,
          PangeaEventTypes.communicationPreferences,
        ),
      );
    } on MatrixException catch (e) {
      // silent-ok: no refusal has been recorded yet; other failures rethrow.
      if (e.error != MatrixError.M_NOT_FOUND) rethrow;
      return const CommunicationPreferences();
    }
  }
}
