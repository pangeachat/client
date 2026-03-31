import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';

class LoginLoadingDialog extends StatefulWidget {
  final Client client;
  final String loginType;
  final String? initialDeviceDisplayName;

  final String? token;
  final AuthenticationIdentifier? identifier;
  final String? user;
  final String? password;
  final VoidCallback? onError;

  const LoginLoadingDialog({
    super.key,
    required this.client,
    required this.loginType,
    this.initialDeviceDisplayName,
    this.token,
    this.identifier,
    this.user,
    this.password,
    this.onError,
  });

  @override
  LoginLoadingDialogState createState() => LoginLoadingDialogState();
}

class LoginLoadingDialogState extends State<LoginLoadingDialog> {
  Object? exception;
  StackTrace? stackTrace;

  final ValueNotifier<InitState?> _initState = ValueNotifier<InitState?>(null);
  Timer? _initStateDebounce;

  @override
  void initState() {
    super.initState();
    _startLogin();
  }

  @override
  void dispose() {
    _initState.dispose();
    _initStateDebounce?.cancel();
    super.dispose();
  }

  String get _initStateLabel {
    final l10n = L10n.of(context);
    return switch (_initState.value) {
      null => l10n.signingInLabel,
      InitState.initializing => l10n.initializingLabel,
      InitState.migratingDatabase => l10n.migratingDatabaseLabel,
      InitState.settingUpEncryption => l10n.settingUpEncryptionLabel,
      InitState.loadingData => l10n.loadingDataLabel,
      InitState.waitingForFirstSync => l10n.loadingDataLabel,
      InitState.finished => l10n.loginFinishedLabel,
      InitState.error => l10n.loginErrorLabel,
    };
  }

  void _setInitState(InitState? state) {
    if (_initStateDebounce?.isActive ?? false) {
      _initStateDebounce!.cancel();
    }
    _initStateDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        _initState.value = state;
      }
    });
  }

  Future<void> _startLogin() async {
    try {
      await widget.client.login(
        widget.loginType,
        identifier: widget.identifier,
        password: widget.password,
        token: widget.token,
        // ignore: deprecated_member_use
        user: widget.user,
        initialDeviceDisplayName: widget.initialDeviceDisplayName,
        onInitStateChanged: _setInitState,
      );
    } catch (e, s) {
      if (!mounted) return;
      widget.onError?.call();
      setState(() {
        exception = e;
        stackTrace = s;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final exception = this.exception;

    return AlertDialog.adaptive(
      title: exception == null
          ? null
          : Icon(
              Icons.error_outline_outlined,
              color: Theme.of(context).colorScheme.error,
              size: 48,
            ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256),
        child: Column(
          spacing: 12.0,
          crossAxisAlignment: .center,
          children: [
            exception != null
                ? Text(
                    exception is MatrixException
                        ? exception.errorMessage
                        : exception.toLocalizedString(context),
                  )
                : ValueListenableBuilder<InitState?>(
                    valueListenable: _initState,
                    builder: (context, initState, child) =>
                        Text(_initStateLabel),
                  ),
            if (exception == null) LinearProgressIndicator(),
          ],
        ),
      ),
      actions: exception == null
          ? [
              AdaptiveDialogAction(
                onPressed: () {
                  widget.onError?.call();
                  Navigator.of(context).pop();
                },
                child: Text(L10n.of(context).cancel),
              ),
            ]
          : [
              AdaptiveDialogAction(
                onPressed: () => Navigator.of(
                  context,
                ).pop(Result.error(exception, stackTrace)),
                child: Text(L10n.of(context).close),
              ),
            ],
      // Pangea#
    );
  }
}
