import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';

extension UiaRequestManager on MatrixState {
  Future uiaRequestHandler(UiaRequest uiaRequest) async {
    final l10n = L10n.of(context);
    final navigatorContext =
        FluffyChatApp.router.routerDelegate.navigatorKey.currentContext ??
        context;
    try {
      if (uiaRequest.state != UiaRequestState.waitForUser ||
          uiaRequest.nextStages.isEmpty) {
        Logs().d('Uia Request Stage: ${uiaRequest.state}');
        return;
      }
      final stage = uiaRequest.nextStages.first;
      Logs().d('Uia Request Stage: $stage');
      switch (stage) {
        case AuthenticationTypes.password:
          final input =
              cachedPassword ??
              (await showTextInputDialog(
                context: navigatorContext,
                title: l10n.pleaseEnterYourPassword,
                okLabel: l10n.ok,
                cancelLabel: l10n.cancel,
                minLines: 1,
                maxLines: 1,
                obscureText: true,
                hintText: '******',
              ));
          if (input == null || input.isEmpty) {
            return uiaRequest.cancel();
          }
          return uiaRequest.completeStage(
            AuthenticationPassword(
              session: uiaRequest.session,
              password: input,
              identifier: AuthenticationUserIdentifier(user: client.userID!),
            ),
          );
        case AuthenticationTypes.emailIdentity:
          if (currentThreepidCreds == null) {
            return uiaRequest.cancel(
              UiaException(L10n.of(context).serverRequiresEmail),
            );
          }
          final auth = AuthenticationThreePidCreds(
            session: uiaRequest.session,
            type: AuthenticationTypes.emailIdentity,
            threepidCreds: ThreepidCreds(
              sid: currentThreepidCreds!.sid,
              clientSecret: currentClientSecret,
            ),
          );
          // #Pangea
          // if (OkCancelResult.ok ==
          //     await showOkCancelAlertDialog(
          //       useRootNavigator: false,
          //       context: navigatorContext,
          //       title: l10n.weSentYouAnEmail,
          //       L10n.of(context).pleaseClickOnLink,
          //       okLabel: l10n.iHaveClickedOnLink,
          //       cancelLabel: l10n.cancel,
          //     )) {
          if (OkCancelResult.ok ==
              await showDialog<OkCancelResult?>(
                useRootNavigator: false,
                barrierDismissible: false,
                context: navigatorContext,
                builder: (context) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  contentPadding: EdgeInsets.all(12.0),
                  title: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 256),
                    child: Text(
                      l10n.weSentYouAnEmail,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  content: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 256),
                    child: Column(
                      mainAxisSize: .min,
                      children: [
                        Text(
                          L10n.of(context).clickOnEmailLink,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        SizedBox(height: 16.0),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16.0),
                            ),
                          ),
                          onPressed: () => Navigator.of(
                            context,
                          ).pop<OkCancelResult>(OkCancelResult.ok),
                          child: Row(
                            mainAxisAlignment: .center,
                            children: [
                              Text(
                                l10n.iHaveClickedOnLink,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 8.0),
                        TextButton(
                          onPressed: () => Navigator.of(
                            context,
                          ).pop<OkCancelResult>(OkCancelResult.cancel),
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                            padding: const EdgeInsets.all(0),
                          ),
                          child: Text(
                            l10n.cancel,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )) {
            // Pangea#
            return uiaRequest.completeStage(auth);
          }
          return uiaRequest.cancel();
        case AuthenticationTypes.dummy:
          return uiaRequest.completeStage(
            AuthenticationData(
              type: AuthenticationTypes.dummy,
              session: uiaRequest.session,
            ),
          );
        default:
          final stageUrl = uiaRequest.params
              .tryGetMap<String, Object?>(stage)
              ?.tryGet<String>('url');
          final fallbackUrl = client.homeserver!.replace(
            path: '/_matrix/client/v3/auth/$stage/fallback/web',
            queryParameters: {'session': uiaRequest.session},
          );
          final url = stageUrl != null
              ? (Uri.tryParse(stageUrl) ?? fallbackUrl)
              : fallbackUrl;

          final consent = await showOkCancelAlertDialog(
            useRootNavigator: false,
            title: l10n.pleaseFollowInstructionsOnWeb,
            context: navigatorContext,
            okLabel: l10n.open,
            cancelLabel: l10n.cancel,
          );
          if (consent != OkCancelResult.ok) return uiaRequest.cancel();

          launchUrl(url, mode: LaunchMode.inAppBrowserView);
          final completer = Completer();
          final listener = AppLifecycleListener(
            onResume: () => completer.complete(),
          );
          await completer.future;
          listener.dispose();

          return uiaRequest.completeStage(
            AuthenticationData(session: uiaRequest.session),
          );
      }
    } catch (e, s) {
      Logs().e('Error while background UIA', e, s);
      return uiaRequest.cancel(e is Exception ? e : Exception(e));
    }
  }
}

class UiaException implements Exception {
  final String reason;

  UiaException(this.reason);

  @override
  String toString() => reason;
}
