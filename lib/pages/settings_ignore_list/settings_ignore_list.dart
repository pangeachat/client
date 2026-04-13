import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import '../../widgets/matrix.dart';
import 'settings_ignore_list_view.dart';

class SettingsIgnoreList extends StatefulWidget {
  final String? initialUserId;

  const SettingsIgnoreList({super.key, this.initialUserId});

  @override
  SettingsIgnoreListController createState() => SettingsIgnoreListController();
}

class SettingsIgnoreListController extends State<SettingsIgnoreList> {
  final TextEditingController controller = TextEditingController();

  // #Pangea
  ValueNotifier<bool> ignoring = ValueNotifier(false);
  // Pangea#

  @override
  void initState() {
    super.initState();
    final initialUserId = widget.initialUserId;
    if (initialUserId != null) {
      controller.text = initialUserId;
    }
  }

  // #Pangea
  @override
  void dispose() {
    controller.dispose();
    ignoring.dispose();
    super.dispose();
  }
  // Pangea#

  String? errorText;

  // #Pangea
  // void ignoreUser(BuildContext context) {
  //   final userId = controller.text.trim();
  //   if (userId.isEmpty) return;
  //   if (!userId.isValidMatrixId || userId.sigil != '@') {
  //     setState(() {
  //       errorText = L10n.of(context).invalidInput;
  //     });
  //     return;
  //   }
  //   setState(() {
  //     errorText = null;
  //   });

  //   final client = Matrix.of(context).client;
  //   showFutureLoadingDialog(
  //     context: context,
  //     future: () => client.ignoreUser(userId),
  //   );
  //   setState(() {});
  //   controller.clear();
  // }
  Future<void> ignoreUser(BuildContext context) async {
    if (ignoring.value) return;
    ignoring.value = true;
    try {
      final userId = controller.text.trim();
      if (userId.isEmpty) return;
      if (!userId.isValidMatrixId || userId.sigil != '@') {
        setState(() {
          errorText = L10n.of(context).invalidInput;
        });
        return;
      }
      setState(() {
        errorText = null;
      });

      final client = Matrix.of(context).client;
      await showFutureLoadingDialog(
        context: context,
        future: () async {
          try {
            final syncFuture = client.onSync.stream.firstWhere(
              (syncUpdate) =>
                  syncUpdate.accountData?.any(
                    (accountData) => accountData.type == 'm.ignored_user_list',
                  ) ??
                  false,
            );
            await client.ignoreUser(userId);
            await syncFuture.timeout(Duration(seconds: 10));
          } catch (e, s) {
            ErrorHandler.logError(
              e: e,
              s: s,
              data: {'userId': userId},
              level: e is TimeoutException
                  ? SentryLevel.warning
                  : SentryLevel.error,
            );
            if (e is! TimeoutException) rethrow;
          }
        },
      );
      if (mounted) setState(() {});
      controller.clear();
    } finally {
      if (mounted) ignoring.value = false;
    }
  }

  Future<void> unignoreUser(String userId) async {
    if (ignoring.value) return;
    ignoring.value = true;
    try {
      final client = Matrix.of(context).client;
      await showFutureLoadingDialog(
        context: context,
        future: () async {
          try {
            final syncFuture = client.onSync.stream.firstWhere(
              (syncUpdate) =>
                  syncUpdate.accountData?.any(
                    (accountData) => accountData.type == 'm.ignored_user_list',
                  ) ??
                  false,
            );
            await client.unignoreUser(userId);
            await syncFuture.timeout(Duration(seconds: 10));
          } catch (e, s) {
            ErrorHandler.logError(
              e: e,
              s: s,
              data: {'userId': userId},
              level: e is TimeoutException
                  ? SentryLevel.warning
                  : SentryLevel.error,
            );
            if (e is! TimeoutException) rethrow;
          }
        },
      );
      if (mounted) setState(() {});
    } finally {
      if (mounted) ignoring.value = false;
    }
  }
  // Pangea#

  @override
  Widget build(BuildContext context) => SettingsIgnoreListView(this);
}
