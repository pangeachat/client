import 'package:fluffychat/pangea/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:matrix/matrix.dart';

class ErrorReporter {
  final BuildContext context;
  final String? message;

  const ErrorReporter(this.context, [this.message]);

  void onErrorCallback(Object error, [StackTrace? stackTrace]) async {
    Logs().e(message ?? 'Error caught', error, stackTrace);
    // #Pangea
    try {
      // Attempt to retrieve the L10n instance using the current context
      final L10n? l10n = L10n.of(context);

      // Check if the L10n instance is null
      if (l10n == null) {
        // Log an error message saying that the localization object is null
        Logs().e('Localization object is null, cannot show error message.');
        // Exits early to prevent further execution
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.oopsSomethingWentWrong, // Use the non-null L10n instance to get the error message
          ),
        ),
      );
    } catch (err) {
      debugPrint("Failed to show error snackbar.");
    } finally {
      ErrorHandler.logError(
        e: error,
        s: stackTrace,
        m: message ?? 'Error caught',
      );
    }
  }
  // final text = '$error\n${stackTrace ?? ''}';
  // await showAdaptiveDialog(
  //   context: context,
  //   builder: (context) => AlertDialog.adaptive(
  //     title: Text(L10n.of(context)!.reportErrorDescription),
  //     content: SizedBox(
  //       height: 256,
  //       width: 256,
  //       child: SingleChildScrollView(
  //         child: HighlightView(
  //           text,
  //           language: 'sh',
  //           theme: shadesOfPurpleTheme,
  //         ),
  //       ),
  //     ),
  //     actions: [
  //       TextButton(
  //         onPressed: () => Navigator.of(context).pop(),
  //         child: Text(L10n.of(context)!.close),
  //       ),
  //       TextButton(
  //         onPressed: () => Clipboard.setData(
  //           ClipboardData(text: text),
  //         ),
  //         child: Text(L10n.of(context)!.copy),
  //       ),
  //       TextButton(
  //         onPressed: () => launchUrl(
  //           AppConfig.newIssueUrl.resolveUri(
  //             Uri(
  //               queryParameters: {
  //                 'template': 'bug_report.yaml',
  //                 'title': '[BUG]: ${message ?? error.toString()}',
  //               },
  //             ),
  //           ),
  //           mode: LaunchMode.externalApplication,
  //         ),
  //         child: Text(L10n.of(context)!.report),
  //       ),
  //     ],
  //   ),
  // );
  // Pangea#
}
