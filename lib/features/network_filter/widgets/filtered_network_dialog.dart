import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/features/authentication/email_address_policy.dart';
import 'package:fluffychat/features/network_filter/filtered_network_controller.dart';
import 'package:fluffychat/features/network_filter/network_help_repo.dart';
import 'package:fluffychat/features/network_filter/network_help_request.dart';
import 'package:fluffychat/features/network_filter/network_host_category.dart';
import 'package:fluffychat/features/network_filter/network_type.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/dialog_text_field.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// What a user on a filtered network can do: the advice for this device, the
/// domains for IT staff, and the "Ask Pangea for help" request. See
/// filtered-network.instructions.md, "What the user sees".
class FilteredNetworkDialog extends StatefulWidget {
  const FilteredNetworkDialog({super.key});

  static final RegExp _phoneBrowser = RegExp(
    'iPhone|iPod|Android',
    caseSensitive: false,
  );

  /// Phones get the mobile-data advice; any other device, the hotspot advice.
  static bool get isPhone =>
      PlatformInfos.isMobile ||
      (kIsWeb && _phoneBrowser.hasMatch(html.window.navigator.userAgent));

  /// Whether the guidance is showing. The banner hides meanwhile: it sits
  /// above the router's Navigator, so it would otherwise cover the dialog.
  static final ValueNotifier<bool> isShowing = ValueNotifier(false);

  /// Opens the guidance on the router's Navigator, because the banner that
  /// opens it sits above that Navigator.
  static Future<void> show() async {
    final context =
        FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;
    if (context == null) {
      ErrorHandler.logError(
        e: StateError('Filtered-network guidance opened with no navigator'),
        data: {},
      );
      return;
    }
    isShowing.value = true;
    try {
      await showDialog(
        context: context,
        builder: (_) => const FilteredNetworkDialog(),
      );
    } finally {
      isShowing.value = false;
    }
  }

  @override
  State<FilteredNetworkDialog> createState() => _FilteredNetworkDialogState();
}

class _FilteredNetworkDialogState extends State<FilteredNetworkDialog> {
  final TextEditingController _email = TextEditingController();
  String? _emailError;

  @override
  void initState() {
    super.initState();
    unawaited(NetworkHelpRepo.refreshStatus());
    unawaited(_prefillEmail());
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _prefillEmail() async {
    if (!Matrix.of(context).client.isLogged()) return;
    try {
      final email = await MatrixState.pangeaController.userController.userEmail
          .timeout(const Duration(seconds: 5));
      if (mounted && email != null && _email.text.isEmpty) {
        _email.text = email;
      }
    } catch (_) {
      // silent-ok: the address lives on the chat server, which this network
      // may block; the user can type it instead.
    }
  }

  Future<void> _copyDomains(String domains) async {
    await Clipboard.setData(ClipboardData(text: domains));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBarAnnounced(
      SnackBar(
        content: Text(L10n.of(context).copiedToClipboard),
        showCloseIcon: true,
      ),
    );
  }

  Future<void> _askForHelp() async {
    final email = _email.text.trim();
    if (!EmailAddressPolicy.isValid(email)) {
      setState(() => _emailError = L10n.of(context).pleaseEnterValidEmail);
      return;
    }
    setState(() => _emailError = null);
    final client = Matrix.of(context).client;
    final controller = FilteredNetworkController.instance;
    await NetworkHelpRepo.submit(
      NetworkHelpRequest(
        email: email,
        accountId: client.isLogged() ? client.userID : null,
        blockedCategories: controller.blocked.value.toList(),
        platform: FilteredNetworkController.platformName,
        networkType: await NetworkType.current(),
        firstBlockedAt: controller.firstBlockedAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final domains = NetworkHostCategory.allAllowlistDomains.join('\n');
    return ValueListenableBuilder<Set<NetworkHostCategory>>(
      valueListenable: FilteredNetworkController.instance.blocked,
      builder: (context, blocked, _) => AlertDialog(
        title: Text(
          blocked.any((category) => category.stopsApp)
              ? l10n.filteredNetworkBlockedTitle
              : l10n.filteredNetworkPartlyBlockedTitle,
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  FilteredNetworkDialog.isPhone
                      ? l10n.filteredNetworkPhoneAdvice
                      : l10n.filteredNetworkComputerAdvice,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.filteredNetworkItHeading,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(l10n.filteredNetworkItBody),
                const SizedBox(height: 8),
                SelectableText(domains),
                TextButton.icon(
                  onPressed: () => _copyDomains(domains),
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(l10n.copy),
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<NetworkHelpStatus>(
                  valueListenable: NetworkHelpRepo.status,
                  builder: (context, status, _) => switch (status) {
                    NetworkHelpStatus.none => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(l10n.filteredNetworkHelpExplanation),
                        const SizedBox(height: 8),
                        DialogTextField(
                          controller: _email,
                          labelText: l10n.yourEmail,
                          keyboardType: TextInputType.emailAddress,
                          errorText: _emailError,
                          onSubmitted: (_) => _askForHelp(),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _askForHelp,
                          child: Text(l10n.filteredNetworkAskForHelp),
                        ),
                      ],
                    ),
                    NetworkHelpStatus.waiting => Text(
                      l10n.filteredNetworkHelpWaiting,
                    ),
                    NetworkHelpStatus.sent => Text(
                      l10n.filteredNetworkHelpSent,
                    ),
                    NetworkHelpStatus.refused => Text(
                      l10n.filteredNetworkHelpRefused,
                    ),
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }
}
