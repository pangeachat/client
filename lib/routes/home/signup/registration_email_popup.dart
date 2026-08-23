import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/features/authentication/email_address_policy.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';

class RegistrationEmailPopup extends StatefulWidget {
  final Future<void> Function() onResendEmail;
  const RegistrationEmailPopup({super.key, required this.onResendEmail});

  @override
  State<RegistrationEmailPopup> createState() => RegistrationEmailPopupState();
}

class RegistrationEmailPopupState extends State<RegistrationEmailPopup> {
  /// Seconds until the resend control is live again. Zero means it is enabled.
  /// It counts down from the moment of the tap rather than from the reply, so
  /// it is also the in-flight guard.
  final ValueNotifier<int> secondsUntilResend = ValueNotifier(0);

  Timer? _countdown;

  @override
  void dispose() {
    _countdown?.cancel();
    secondsUntilResend.dispose();
    super.dispose();
  }

  Future<void> resendEmail() async {
    if (secondsUntilResend.value > 0) return;
    _startCountdown();
    try {
      await widget.onResendEmail();
    } catch (_) {
      // A send that never happened should not cost the learner the wait.
      _countdown?.cancel();
      secondsUntilResend.value = 0;
      rethrow;
    }
  }

  void _startCountdown() {
    secondsUntilResend.value = EmailAddressPolicy.resendCooldown.inSeconds;
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      secondsUntilResend.value--;
      if (secondsUntilResend.value <= 0) timer.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Semantics(
        label: l10n.weSentYouAnEmail,
        liveRegion: true,
        container: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  spacing: 12.0,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: Semantics(
                        container: true,
                        child: Text(
                          l10n.weSentYouAnEmail,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    Semantics(
                      container: true,
                      child: Text(
                        l10n.clickOnEmailLinkDesc,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
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
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            l10n.iHaveClickedOnLink,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                    MergeSemantics(
                      child: Row(
                        spacing: 4.0,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              l10n.didntReceiveEmail,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          ValueListenableBuilder(
                            valueListenable: secondsUntilResend,
                            builder: (context, seconds, _) => TextButton(
                              onPressed: seconds > 0 ? null : resendEmail,
                              child: Text(
                                seconds > 0
                                    ? l10n.resendInSeconds(seconds)
                                    : l10n.resend,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Close button
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  tooltip: L10n.of(context).close,
                  icon: const Icon(Icons.close, size: 18),
                  splashRadius: 18,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
