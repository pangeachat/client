import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/settings_notifications/push_rule_extensions.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/languages/language_constants.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/local_notifications_extension.dart';
import '../../widgets/matrix.dart';
import 'settings_notifications_view.dart';

class SettingsNotifications extends StatefulWidget {
  const SettingsNotifications({super.key});

  @override
  SettingsNotificationsController createState() =>
      SettingsNotificationsController();
}

class SettingsNotificationsController extends State<SettingsNotifications> {
  bool isLoading = false;

  void onPusherTap(Pusher pusher) async {
    final delete = await showModalActionPopup<bool>(
      context: context,
      title: pusher.deviceDisplayName,
      message: '${pusher.appDisplayName} (${pusher.appId})',
      cancelLabel: L10n.of(context).cancel,
      actions: [
        AdaptiveModalAction(
          label: L10n.of(context).delete,
          isDestructive: true,
          value: true,
        ),
      ],
    );
    if (delete != true) return;

    final success = await showFutureLoadingDialog(
      context: context,
      future: () => Matrix.of(context).client.deletePusher(
        PusherId(appId: pusher.appId, pushkey: pusher.pushkey),
      ),
    );

    if (success.error != null) return;

    setState(() {
      pusherFuture = null;
    });
  }

  Future<List<Pusher>?>? pusherFuture;

  void togglePushRule(PushRuleKind kind, PushRule pushRule) async {
    setState(() {
      isLoading = true;
    });
    try {
      final updateFromSync = Matrix.of(context).client.onSync.stream
          .where(
            (syncUpdate) =>
                syncUpdate.accountData?.any(
                  (accountData) => accountData.type == 'm.push_rules',
                ) ??
                false,
          )
          .first;
      await Matrix.of(
        context,
      ).client.setPushRuleEnabled(kind, pushRule.ruleId, !pushRule.enabled);
      await updateFromSync;
    } catch (e, s) {
      Logs().w('Unable to toggle push rule', e, s);
      if (!mounted) return;
      // #Pangea
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      // Pangea#
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void editPushRule(PushRule rule, PushRuleKind kind) async {
    final theme = Theme.of(context);
    final action = await showAdaptiveDialog<PushRuleDialogAction>(
      context: context,
      builder: (context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256),
        child: AlertDialog.adaptive(
          title: Text(rule.getPushRuleName(L10n.of(context))),
          content: Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Material(
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              color: theme.colorScheme.surfaceContainer,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  prettyJson(rule.toJson()),
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
              ),
            ),
          ),
          actions: [
            AdaptiveDialogAction(
              onPressed: Navigator.of(context).pop,
              child: Text(L10n.of(context).close),
            ),
            if (!rule.ruleId.startsWith('.m.'))
              AdaptiveDialogAction(
                onPressed: () =>
                    Navigator.of(context).pop(PushRuleDialogAction.delete),
                child: Text(
                  L10n.of(context).delete,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (!mounted) return;
    switch (action) {
      case PushRuleDialogAction.delete:
        final consent = await showOkCancelAlertDialog(
          context: context,
          title: L10n.of(context).areYouSure,
          message: L10n.of(context).deletePushRuleCanNotBeUndone,
          okLabel: L10n.of(context).delete,
          isDestructive: true,
        );
        if (consent != OkCancelResult.ok) return;
        if (!mounted) return;
        setState(() {
          isLoading = true;
        });
        try {
          final updateFromSync = Matrix.of(context).client.onSync.stream
              .where(
                (syncUpdate) =>
                    syncUpdate.accountData?.any(
                      (accountData) => accountData.type == 'm.push_rules',
                    ) ??
                    false,
              )
              .first;
          await Matrix.of(context).client.deletePushRule(kind, rule.ruleId);
          await updateFromSync;
        } catch (e, s) {
          Logs().w('Unable to delete push rule', e, s);
          if (!mounted) return;
          // #Pangea
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          // Pangea#
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
        } finally {
          if (mounted) {
            setState(() {
              isLoading = false;
            });
          }
        }
        return;
    }
  }

  // #Pangea
  final ValueNotifier<double> volumeNotifier = ValueNotifier<double>(
    AppSettings.volume.value,
  );

  void updateVolume(double value) {
    volumeNotifier.value = value;
    AppSettings.volume.setItem(value);
  }

  Future<void> requestNotificationPermission() async {
    await Matrix.of(context).requestNotificationPermission();
    if (mounted) setState(() {});
  }

  List<ThirdPartyIdentifier>? _thirdPartyIds;

  Future<bool> get emailNotificationsEnabled async {
    List<Pusher> pushers = [];
    Set<String> emails = {};

    try {
      pusherFuture ??= Matrix.of(context).client.getPushers();
      pushers = (await pusherFuture!) ?? [];
      if (pushers.isEmpty) return false;
      if (!pushers.any((pusher) => pusher.kind == 'email')) {
        return false;
      }

      _thirdPartyIds ??= await Matrix.of(context).client.getAccount3PIDs();
      emails = _thirdPartyIds!
          .where((p) => p.medium == ThirdPartyIdentifierMedium.email)
          .map((p) => p.address)
          .toSet();
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'pushers': pushers.map((p) => p.toJson()).toList(),
          'thirdPartyIds': _thirdPartyIds?.map((id) => id.toJson()).toList(),
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

  Future<void> setEmailNotificationsEnabled(bool enable) async {
    List<Pusher> pushers = [];
    Set<String> emails = {};

    try {
      pusherFuture ??= Matrix.of(context).client.getPushers();
      pushers = (await pusherFuture!) ?? [];
      _thirdPartyIds ??= await Matrix.of(context).client.getAccount3PIDs();
      emails = _thirdPartyIds!
          .where((p) => p.medium == ThirdPartyIdentifierMedium.email)
          .map((p) => p.address)
          .toSet();
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'enable': enable,
          'pushers': pushers.map((p) => p.toJson()).toList(),
          'thirdPartyIds': _thirdPartyIds?.map((id) => id.toJson()).toList(),
        },
      );
    }

    try {
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
            await Matrix.of(context).client.postPusher(pusher);
          }
        }
      } else {
        for (final pusher in pushers.where(
          (pusher) => pusher.kind == 'email' && pusher.appId == 'm.email',
        )) {
          await Matrix.of(context).client.deletePusher(
            PusherId(appId: pusher.appId, pushkey: pusher.pushkey),
          );
        }
      }
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'enable': enable,
          'pushers': pushers.map((p) => p.toJson()).toList(),
          'thirdPartyIds': _thirdPartyIds?.map((id) => id.toJson()).toList(),
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toLocalizedString(context)),
          showCloseIcon: true,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          pusherFuture = null;
        });
      }
    }
  }
  // Pangea#

  @override
  Widget build(BuildContext context) => SettingsNotificationsView(this);
}

enum PushRuleDialogAction { delete }

String prettyJson(Map<String, Object?> json) {
  const decoder = JsonDecoder();
  const encoder = JsonEncoder.withIndent('    ');
  final object = decoder.convert(jsonEncode(json));
  return encoder.convert(object);
}
