import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/languages/language_constants.dart';

/// The pushers to post and delete so the account's Synapse email pushers,
/// which send missed-message emails, match the person's choice.
class EmailPusherChanges {
  static const String pusherKind = 'email';
  static const String pusherAppId = 'm.email';
  static const String pusherAppDisplayName = 'Email Notifications';

  final Set<String> addressesToAdd;
  final List<PusherId> pushersToRemove;

  const EmailPusherChanges._({
    required this.addressesToAdd,
    required this.pushersToRemove,
  });

  factory EmailPusherChanges.toMatch({
    required bool emailsEnabled,
    required Set<String> addresses,
    required List<Pusher> pushers,
  }) {
    final emailPushers = pushers.where(isEmailPusher);
    if (!emailsEnabled) {
      return EmailPusherChanges._(
        addressesToAdd: const {},
        pushersToRemove: emailPushers
            .map((p) => PusherId(appId: p.appId, pushkey: p.pushkey))
            .toList(),
      );
    }
    return EmailPusherChanges._(
      addressesToAdd: addresses.difference(
        emailPushers.map((p) => p.pushkey).toSet(),
      ),
      pushersToRemove: const [],
    );
  }

  static bool isEmailPusher(Pusher pusher) =>
      pusher.kind == pusherKind && pusher.appId == pusherAppId;

  static Pusher pusherFor(String address) => Pusher(
    kind: pusherKind,
    pushkey: address,
    appId: pusherAppId,
    appDisplayName: pusherAppDisplayName,
    deviceDisplayName: address,
    lang: LanguageKeys.defaultLanguage,
    data: PusherData(),
  );
}
