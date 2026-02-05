import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

class ErrorReporter {
  final BuildContext? context;
  final String? message;

  const ErrorReporter(this.context, [this.message]);

  static const Set<String> ingoredTypes = {
    "IOException",
    "ClientException",
    "SocketException",
    "TlsException",
    "HandshakeException",
  };

  void onErrorCallback(Object error, [StackTrace? stackTrace]) {
    if (ingoredTypes.contains(error.runtimeType.toString())) return;
    Logs().e(message ?? 'Error caught', error, stackTrace);
    // #Pangea
    // final text = '$error\n${stackTrace ?? ''}';
    // return _onErrorCallback(text);
    if (context == null) return;
    try {
      // Attempt to retrieve the L10n instance using the current context
      final L10n l10n = L10n.of(context!);
      ScaffoldMessenger.of(context!).showSnackBar(
        SnackBar(
          content: Text(
            l10n.oopsSomethingWentWrong, // Use the non-null L10n instance to get the error message
          ),
          // #Pangea
          showCloseIcon: true,
          // Pangea#
        ),
      );
    } catch (err) {
      debugPrint("Failed to show error snackbar.");
    } finally {
      ErrorHandler.logError(
        e: error,
        s: stackTrace,
        m: message ?? 'Error caught',
        data: {},
      );
    }
    // Pangea#
  }

  // #Pangea
  // void _onErrorCallback(String text) async {
  //   await showAdaptiveDialog(
  //     context: context!,
  //     builder: (context) => AlertDialog.adaptive(
  //       title: Text(L10n.of(context).reportErrorDescription),
  //       content: SizedBox(
  //         height: 256,
  //         width: 256,
  //         child: SingleChildScrollView(
  //           child: Text(
  //             text,
  //             style: const TextStyle(fontSize: 14, fontFamily: 'RobotoMono'),
  //           ),
  //         ),
  //       ),
  //       actions: [
  //         AdaptiveDialogAction(
  //           onPressed: () => Navigator.of(context).pop(),
  //           child: Text(L10n.of(context).close),
  //         ),
  //         AdaptiveDialogAction(
  //           onPressed: () => Clipboard.setData(ClipboardData(text: text)),
  //           child: Text(L10n.of(context).copy),
  //         ),
  //         AdaptiveDialogAction(
  //           onPressed: () => launchUrl(
  //             AppConfig.newIssueUrl.resolveUri(
  //               Uri(queryParameters: {'template': 'bug_report.yaml'}),
  //             ),
  //             mode: LaunchMode.externalApplication,
  //           ),
  //           child: Text(L10n.of(context).report),
  //         ),
  //       ],
  //     ),
  //   );
  // }
  // Pangea#
}
