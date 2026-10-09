import 'package:flutter/material.dart';

import 'package:fluffychat/features/student_invitations/pending_claims_flow.dart';
import 'package:fluffychat/features/student_invitations/student_invitation_api.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';

/// The mandatory "Your teacher will manage this account." checkbox with the
/// module's full managed-account disclosure under it (SPEC §4 Student). The
/// one widget on all three confirmation screens: the invite link's
/// sign-up/sign-in card, the in-app prompt, and the Canvas link page.
///
/// The box cannot be ticked until [disclosure] has loaded: agreeing to text
/// the student has not seen is not a confirmation. When the load failed,
/// [onRetry] offers another try.
class ManagedConsentPanel extends StatelessWidget {
  final String? courseName;
  final String? maskedEmailHint;
  final ManagedDisclosure? disclosure;
  final bool checked;
  final ValueChanged<bool> onChanged;
  final bool loadFailed;
  final VoidCallback? onRetry;

  const ManagedConsentPanel({
    super.key,
    required this.courseName,
    this.maskedEmailHint,
    required this.disclosure,
    required this.checked,
    required this.onChanged,
    this.loadFailed = false,
    this.onRetry,
  });

  static const Key checkboxKey = ValueKey('managedConsentCheckbox');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final course = courseName ?? l10n.seatInviteYourCourse;
    final disclosure = this.disclosure;
    final hint = maskedEmailHint;

    final Widget details;
    if (disclosure != null) {
      details = Text(
        disclosure.textFor(course),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    } else if (loadFailed) {
      details = Row(
        spacing: 8.0,
        children: [
          Expanded(
            child: Text(
              l10n.seatInviteDisclosureFailed,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(l10n.tryAgain)),
        ],
      );
    } else {
      details = const Center(
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: CircularProgressIndicator.adaptive(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 4.0,
      children: [
        if (hint != null)
          Text(
            l10n.seatInviteEmailHint(hint),
            style: theme.textTheme.bodySmall,
          ),
        CheckboxListTile(
          key: checkboxKey,
          value: checked,
          onChanged: disclosure == null ? null : (v) => onChanged(v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            l10n.seatInviteManagedCheckbox,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        details,
      ],
    );
  }
}

/// Loads the disclosure for a confirmation screen, with a retry.
mixin ManagedDisclosureLoader<T extends StatefulWidget> on State<T> {
  StudentInvitationApi get disclosureApi;

  ManagedDisclosure? disclosure;
  bool disclosureFailed = false;

  @override
  void initState() {
    super.initState();
    loadDisclosure();
  }

  Future<void> loadDisclosure() async {
    if (disclosureFailed) setState(() => disclosureFailed = false);
    try {
      final loaded = await disclosureApi.disclosure();
      if (mounted) setState(() => disclosure = loaded);
    } catch (_) {
      // silent-ok: shown on screen as the load failure with a retry; the
      // checkbox stays disabled, so nothing can be confirmed meanwhile.
      if (mounted) setState(() => disclosureFailed = true);
    }
  }
}

/// The in-app confirmation (the pending prompt, and the invite or Canvas
/// confirmation after sign-in when the box was not ticked before it).
/// Resolves to the disclosure version the student ticked and confirmed, or
/// null for "Not now".
class ManagedConsentDialog extends StatefulWidget {
  final ConsentRequest request;
  final StudentInvitationApi api;

  const ManagedConsentDialog({
    super.key,
    required this.request,
    required this.api,
  });

  static const Key confirmKey = ValueKey('managedConsentConfirm');
  static const Key notNowKey = ValueKey('managedConsentNotNow');

  static Future<int?> show(
    BuildContext context,
    ConsentRequest request, {
    required StudentInvitationApi api,
  }) => showAdaptiveDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ManagedConsentDialog(request: request, api: api),
  );

  @override
  State<ManagedConsentDialog> createState() => _ManagedConsentDialogState();
}

class _ManagedConsentDialogState extends State<ManagedConsentDialog>
    with ManagedDisclosureLoader {
  bool _checked = false;

  @override
  StudentInvitationApi get disclosureApi => widget.api;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final course = widget.request.courseName ?? l10n.seatInviteYourCourse;
    final version = disclosure?.version;
    return AlertDialog.adaptive(
      title: Text(l10n.seatInvitePromptTitle(course)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Material(
            type: MaterialType.transparency,
            child: ManagedConsentPanel(
              courseName: widget.request.courseName,
              maskedEmailHint: widget.request.maskedEmailHint,
              disclosure: disclosure,
              loadFailed: disclosureFailed,
              onRetry: loadDisclosure,
              checked: _checked,
              onChanged: (v) => setState(() => _checked = v),
            ),
          ),
        ),
      ),
      actions: [
        AdaptiveDialogAction(
          key: ManagedConsentDialog.notNowKey,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.seatInviteNotNow),
        ),
        AdaptiveDialogAction(
          key: ManagedConsentDialog.confirmKey,
          onPressed: _checked && version != null
              ? () => Navigator.of(context).pop(version)
              : null,
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}
