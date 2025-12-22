import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_linkify/flutter_linkify.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';

class SSODialog extends StatefulWidget {
  final Future<void> Function() future;
  const SSODialog({
    super.key,
    required this.future,
  });

  @override
  SSODialogState createState() => SSODialogState();
}

class SSODialogState extends State<SSODialog> {
  Timer? _hintTimer;
  bool _showHint = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _runFuture();
    _hintTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _showHint = true);
      }
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  Future<void> _runFuture() async {
    try {
      await widget.future();
    } catch (e) {
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: _error == null
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 256),
              child: Text(L10n.of(context).ssoDialogTitle),
            )
          : Icon(
              Icons.error_outline_outlined,
              color: Theme.of(context).colorScheme.error,
              size: 48,
            ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256),
        child: _error == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableLinkify(
                    text: L10n.of(context).ssoDialogDesc,
                    textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
                    linkStyle: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      decorationColor: Theme.of(context).colorScheme.primary,
                    ),
                    options: const LinkifyOptions(humanize: false),
                    onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
                  ),
                  const SizedBox(height: 16),
                  _showHint
                      ? Text(
                          L10n.of(context).ssoDialogHelpText,
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      : const SizedBox(
                          height: 16.0,
                          width: 16.0,
                          child: CircularProgressIndicator.adaptive(),
                        ),
                ],
              )
            : Text(_error!.toLocalizedString(context)),
      ),
      actions: [
        AdaptiveDialogAction(
          onPressed: () =>
              Navigator.of(context).pop<OkCancelResult>(OkCancelResult.cancel),
          child: Text(L10n.of(context).cancel),
        ),
      ],
    );
  }
}
