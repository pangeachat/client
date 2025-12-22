import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_linkify/flutter_linkify.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/url_launcher.dart';

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
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: Container(
        padding: const EdgeInsets.all(12.0),
        constraints: const BoxConstraints(maxWidth: 450),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: Navigator.of(context).pop,
                icon: const Icon(Icons.close),
              ),
            ),
            _error == null
                ? Text(
                    L10n.of(context).ssoDialogTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  )
                : Icon(
                    Icons.error_outline_outlined,
                    color: Theme.of(context).colorScheme.error,
                    size: 48,
                  ),
            Container(
              alignment: Alignment.center,
              constraints: const BoxConstraints(minHeight: 150),
              padding: const EdgeInsets.all(4.0),
              child: Column(
                spacing: 16.0,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null)
                    Text(
                      _error!.toLocalizedString(context),
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    )
                  else ...[
                    SelectableLinkify(
                      text: L10n.of(context).ssoDialogDesc,
                      textScaleFactor:
                          MediaQuery.textScalerOf(context).scale(1),
                      linkStyle: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        decorationColor: Theme.of(context).colorScheme.primary,
                      ),
                      options: const LinkifyOptions(humanize: false),
                      onOpen: (url) =>
                          UrlLauncher(context, url.url).launchUrl(),
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    _showHint
                        ? Text(
                            L10n.of(context).ssoDialogHelpText,
                            style: Theme.of(context).textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          )
                        : const SizedBox(
                            height: 16.0,
                            width: 16.0,
                            child: CircularProgressIndicator.adaptive(),
                          ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
