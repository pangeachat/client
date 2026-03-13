import 'dart:async';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/languages/language_constants.dart';
import 'package:fluffychat/pangea/notifications/notifications_settings_model.dart';

extension NotificationsExtension on Client {
  NotificationsSettingsModel get notificationSettings {
    final data = accountData[PangeaEventTypes.notificationSettings];
    if (data != null) {
      return NotificationsSettingsModel.fromJson(data.content);
    }
    return const NotificationsSettingsModel();
  }

  Future<void> setNotificationsSettings(
    NotificationsSettingsModel model,
  ) async {
    final prevModel = notificationSettings;
    if (model == prevModel) return;

    await setAccountData(
      userID!,
      PangeaEventTypes.notificationSettings,
      model.toJson(),
    );

    final updatedModel = notificationSettings;
    if (model == updatedModel) {
      try {
        await onSync.stream
            .firstWhere((sync) => sync.accountData != null)
            .timeout(Duration(seconds: 10));
      } catch (e, s) {
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {
            'client_user_id': userID,
            'expected_model': model.toJson(),
            'updated_model': updatedModel.toJson(),
          },
          level: e is TimeoutException
              ? SentryLevel.warning
              : SentryLevel.error,
        );
      }
    }
  }

  Future<bool> get emailNotificationsEnabled async {
    List<Pusher> pushers = [];
    Set<String> emails = {};

    try {
      pushers = (await getPushers()) ?? [];
      if (pushers.isEmpty) return false;
      if (!pushers.any((pusher) => pusher.kind == 'email')) {
        return false;
      }

      final thirdPartyIds = (await getAccount3PIDs()) ?? [];
      emails = thirdPartyIds
          .where((p) => p.medium == ThirdPartyIdentifierMedium.email)
          .map((p) => p.address)
          .toSet();
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'pushers': pushers.map((p) => p.toJson()).toList(),
          'emails': emails,
        },
      );
    }

    if (emails.isEmpty) return false;
    return emails.every(
      (email) => pushers.any(
        (pusher) =>
            pusher.kind == 'email' &&
            pusher.pushkey == email &&
            pusher.appId == 'm.email',
      ),
    );
  }

  Future<void> setEnableEmailNotifs(bool enable) async {
    final pushers = (await getPushers()) ?? [];
    final thirdPartyIds = (await getAccount3PIDs()) ?? [];
    final emails = thirdPartyIds
        .where((p) => p.medium == ThirdPartyIdentifierMedium.email)
        .map((p) => p.address)
        .toSet();

    if (enable) {
      for (final email in emails) {
        if (!pushers.any(
          (pusher) =>
              pusher.kind == 'email' &&
              pusher.pushkey == email &&
              pusher.appId == 'm.email',
        )) {
          final pusher = Pusher(
            kind: 'email',
            pushkey: email,
            appId: 'm.email',
            appDisplayName: 'Email Notifications',
            deviceDisplayName: email,
            lang: LanguageKeys.defaultLanguage,
            data: PusherData(),
          );
          await postPusher(pusher);
        }
      }
    } else {
      for (final pusher in pushers.where(
        (pusher) => pusher.kind == 'email' && pusher.appId == 'm.email',
      )) {
        await deletePusher(
          PusherId(appId: pusher.appId, pushkey: pusher.pushkey),
        );
      }
    }

    final updated = notificationSettings.copyWith(enableEmailNotifs: enable);
    await setNotificationsSettings(updated);
  }
}
