import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:get_storage/get_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/env_loader.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

/// The team's hidden environment switcher on the login page
/// (deployment.instructions.md § Environment switcher). Tapping [child]
/// [tapsToOpen] times in quick succession asks for the team code, then offers
/// the build's own environment and the one its `.env` names. Off iOS and
/// Android, or when the `.env` names no other environment, it is just
/// [child].
class EnvironmentSwitcherTapTarget extends StatefulWidget {
  static const int tapsToOpen = 7;
  static const Duration maxGapBetweenTaps = Duration(seconds: 1);
  static const String teamCode = 'pangeaqa';

  final Widget child;

  const EnvironmentSwitcherTapTarget({required this.child, super.key});

  @override
  State<EnvironmentSwitcherTapTarget> createState() =>
      _EnvironmentSwitcherTapTargetState();
}

class _EnvironmentSwitcherTapTargetState
    extends State<EnvironmentSwitcherTapTarget> {
  int _taps = 0;
  DateTime? _lastTap;

  void _onTap() {
    final now = DateTime.now();
    final lastTap = _lastTap;
    final inARow =
        lastTap != null &&
        now.difference(lastTap) <=
            EnvironmentSwitcherTapTarget.maxGapBetweenTaps;
    _taps = inARow ? _taps + 1 : 1;
    _lastTap = now;
    if (_taps < EnvironmentSwitcherTapTarget.tapsToOpen) return;
    _taps = 0;
    unawaited(_switchEnvironment());
  }

  Future<void> _switchEnvironment() async {
    final code = await showTextInputDialog(
      context: context,
      title: L10n.of(context).teamCode,
      autocorrect: false,
    );
    if (!mounted || code?.trim() != EnvironmentSwitcherTapTarget.teamCode) {
      return;
    }

    final chosen = await showModalActionPopup<String>(
      context: context,
      cancelLabel: L10n.of(context).cancel,
      actions: [
        for (final environment in [
          Environment.buildEnvironment,
          Environment.otherEnvironment,
        ])
          AdaptiveModalAction(
            value: environment,
            label: environment,
            isDefaultAction: environment == Environment.activeEnvironment,
          ),
      ],
    );
    if (!mounted || chosen == null || chosen == Environment.activeEnvironment) {
      return;
    }

    AppConfigOverride? override;
    if (chosen != Environment.buildEnvironment) {
      // Shows the error and reports it to Sentry when the download fails.
      final download = await showFutureLoadingDialog(
        context: context,
        future: () async => AppConfigOverride.fromEnvFile(
          chosen,
          await EnvLoader.fetchFromWebApp(Environment.environmentSwitcherUrl!),
        ),
      );
      if (!mounted || download.isError) return;
      override = download.result;
    }

    await Environment.setAppConfigOverride(override);
    await _eraseStorageFromOldEnvironment();
    if (!mounted) return;
    // Never closes: the switch applies on the next launch, so nothing in this
    // one may run on against the new environment.
    unawaited(
      showAdaptiveDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog.adaptive(
            content: Text(L10n.of(context).reopenAppToFinishSwitching),
          ),
        ),
      ),
    );
  }

  /// Erases every GetStorage box except the switch itself. GetStorage keeps
  /// each box as `<name>.gs` in the documents directory, so listing those
  /// files finds boxes a sign-out keeps and boxes no code in this launch has
  /// opened, both of which a list of known names would miss.
  Future<void> _eraseStorageFromOldEnvironment() async {
    const boxFileExtension = '.gs';
    final directory = await getApplicationDocumentsDirectory();
    final boxNames = directory
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where((fileName) => fileName.endsWith(boxFileExtension))
        .map(
          (fileName) =>
              fileName.substring(0, fileName.length - boxFileExtension.length),
        )
        .where((name) => name != Environment.appConfigurationStorageName)
        .toList();

    if (boxNames.isEmpty) {
      // The switch's own box is always there, so finding no other means the
      // storage layout changed and nothing from the old environment was
      // erased.
      ErrorHandler.logError(
        e: Exception('Environment switch found no storage boxes to erase'),
        s: StackTrace.current,
        data: {'directory': directory.path},
      );
      return;
    }

    for (final name in boxNames) {
      await GetStorage.init(name);
      await GetStorage(name).erase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final offered =
        !kIsWeb &&
        {
          TargetPlatform.android,
          TargetPlatform.iOS,
        }.contains(defaultTargetPlatform);
    if (!offered || Environment.environmentSwitcherUrl == null) {
      return widget.child;
    }
    return GestureDetector(
      onTap: _onTap,
      // Hidden: a screen reader must not announce the heading as tappable.
      excludeFromSemantics: true,
      child: widget.child,
    );
  }
}
