import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';

/// Displays a loading dialog which reacts to the given [future]. The dialog
/// will be dismissed and the value will be returned when the future completes.
/// If an error occured, then [onError] will be called and this method returns
/// null.
Future<Result<T>> showFutureLoadingDialog<T>({
  required BuildContext context,
  Future<T> Function()? future,
  Future<T> Function(void Function(double?) setProgress)? futureWithProgress,
  // Replaces the label with what the future is doing now, for a wait long
  // enough that the learner should be told (interaction-latency doc).
  Future<T> Function(void Function(String) setStatus)? futureWithStatus,
  String? title,
  String? backLabel,
  bool barrierDismissible = false,
  bool delay = true,
  ExceptionContext? exceptionContext,
  bool ignoreError = false,
  // #Pangea
  bool Function(Object)? showError,
  Object? Function(Object, StackTrace?)? onError,
  String? Function()? onSuccess,
  VoidCallback? onDismiss,
  bool popOnSuccess = true,
  // Pangea#
}) async {
  assert(
    future != null || futureWithProgress != null || futureWithStatus != null,
  );
  final onProgressStream = StreamController<double?>();
  final onStatusStream = futureWithStatus == null
      ? null
      : StreamController<String>();
  final futureExec =
      futureWithProgress?.call(onProgressStream.add) ??
      futureWithStatus?.call(onStatusStream!.add) ??
      future!();
  final resultFuture = ResultFuture(futureExec);

  if (delay) {
    var i = 3;
    while (i > 0) {
      final result = resultFuture.result;
      if (result != null) {
        if (result.isError) break;
        return result;
      }
      await Future.delayed(const Duration(milliseconds: 100));
      i--;
    }
  }

  // #Pangea
  if (!context.mounted) {
    try {
      final result = await futureExec;
      return Result.value(result);
    } catch (e, s) {
      return Result.error(e, s);
    }
  }
  // Pangea#

  final result = await showAdaptiveDialog<Result<T>>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (BuildContext context) => LoadingDialog<T>(
      future: futureExec,
      title: title,
      backLabel: backLabel,
      exceptionContext: exceptionContext,
      onProgressStream: onProgressStream.stream,
      onStatusStream: onStatusStream?.stream,
      // #Pangea
      showError: showError,
      onError: onError,
      onDismiss: onDismiss,
      onSuccess: onSuccess,
      popOnSuccess: true,
      // Pangea#
    ),
  );
  return result ??
      Result.error(Exception('FutureDialog canceled'), StackTrace.current);
}

class LoadingDialog<T> extends StatefulWidget {
  final String? title;
  final String? backLabel;
  final Future<T> future;
  final ExceptionContext? exceptionContext;
  final Stream<double?> onProgressStream;
  final Stream<String>? onStatusStream;
  // #Pangea
  final bool Function(Object)? showError;
  final Object? Function(Object, StackTrace?)? onError;
  final String? Function()? onSuccess;
  final VoidCallback? onDismiss;
  final bool popOnSuccess;
  // Pangea#

  const LoadingDialog({
    super.key,
    required this.future,
    this.title,
    this.backLabel,
    this.exceptionContext,
    required this.onProgressStream,
    this.onStatusStream,
    // #Pangea
    this.showError,
    this.onError,
    this.onSuccess,
    this.onDismiss,
    this.popOnSuccess = true,
    // Pangea#
  });

  @override
  LoadingDialogState<T> createState() => LoadingDialogState<T>();
}

class LoadingDialogState<T> extends State<LoadingDialog> {
  Object? exception;
  StackTrace? stackTrace;
  // #Pangea
  Object? _result;
  String? _successMessage;
  // Pangea#
  String? _status;
  StreamSubscription<String>? _statusSubscription;
  Timer? _statusDebounce;

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _statusDebounce?.cancel();
    super.dispose();
  }

  /// The first status shows at once. A later one shows only once it has held
  /// for 250 ms, so steps that finish quickly don't flash past unread — the
  /// same delay as the login dialog's.
  void _onStatus(String status) {
    _statusDebounce?.cancel();
    if (_status == null) {
      setState(() => _status = status);
      return;
    }
    _statusDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _status = status);
    });
  }

  @override
  void initState() {
    super.initState();
    _statusSubscription = widget.onStatusStream?.listen(_onStatus);
    // #Pangea
    // widget.future.then(
    //   (result) => Navigator.of(context).pop<Result<T>>(Result.value(result)),
    //   onError: (e, s) => setState(() {
    //     exception = e;
    //     stackTrace = s;
    //   }),
    // );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.future.then(
        (result) {
          if (mounted && widget.onSuccess != null) {
            _successMessage = widget.onSuccess!();
            _result = result;
            setState(() {});
          } else if (mounted && Navigator.of(context).canPop()) {
            // #Pangea
            // Navigator.of(context).pop<Result<T>>(Result.value(result));
            if (widget.popOnSuccess) {
              Navigator.of(context).pop<Result<T>>(Result.value(result));
            }
            // Pangea#
          }
        },
        onError: (e, s) {
          ErrorHandler.logError(e: e, s: s, data: {});
          if (widget.showError != null && !widget.showError!(e)) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop<Result<T>>(Result.error(e, s));
            }
            return;
          }

          if (mounted) {
            setState(() {
              exception = widget.onError?.call(e, s) ?? e;
              stackTrace = s;
            });
          }
        },
      ),
    );
    // Pangea#
  }

  @override
  Widget build(BuildContext context) {
    final exception = this.exception;
    // #Pangea
    // final titleLabel = exception != null
    //     ? exception.toLocalizedString(context, widget.exceptionContext)
    //     : widget.title ?? L10n.of(context).loadingPleaseWait;
    final titleLabel = exception != null
        ? exception.toLocalizedString(context, widget.exceptionContext)
        : _successMessage ??
              _status ??
              widget.title ??
              L10n.of(context).loadingPleaseWait;
    // Pangea#

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
        // A dialog that reports what it is doing is laid out like the login
        // dialog: the status centred over a progress bar.
        child:
            widget.onStatusStream != null &&
                exception == null &&
                _successMessage == null
            ? Column(
                spacing: 12.0,
                mainAxisSize: .min,
                children: [
                  Semantics(
                    container: true,
                    liveRegion: true,
                    child: Text(titleLabel, textAlign: TextAlign.center),
                  ),
                  const LinearProgressIndicator(),
                ],
              )
            : Row(
                crossAxisAlignment: .center,
                children: [
                  // #Pangea
                  // if (exception == null) ...[
                  if (exception == null && _successMessage == null) ...[
                    // Pangea#
                    StreamBuilder(
                      stream: widget.onProgressStream,
                      builder: (context, snapshot) =>
                          CircularProgressIndicator.adaptive(
                            value: snapshot.data,
                          ),
                    ),
                    const SizedBox(width: 20),
                  ],
                  Expanded(
                    // #Pangea: a live region so the settled result (error or success)
                    // is announced to screen readers; the loading state is already
                    // read when the dialog opens, so the region only flips on once
                    // there is a result (WCAG 4.1.3, #7203).
                    child: Semantics(
                      liveRegion: exception != null || _successMessage != null,
                      child: Text(
                        titleLabel,
                        maxLines: 4,
                        // textAlign: exception == null ? TextAlign.left : null,
                        textAlign: exception == null && _successMessage == null
                            ? TextAlign.left
                            : null,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Pangea#
                  ),
                ],
              ),
      ),
      // #Pangea
      // actions: exception == null
      //     ? null
      //     : [
      //         AdaptiveDialogAction(
      //           onPressed: () => Navigator.of(
      //             context,
      //           ).pop<Result<T>>(Result.error(exception, stackTrace)),
      //           child: Text(widget.backLabel ?? L10n.of(context).close),
      //         ),
      //       ],
      actions: _successMessage != null
          ? [
              AdaptiveDialogAction(
                onPressed: () => Navigator.of(
                  context,
                ).pop<Result<T>>(Result.value(_result as T)),
                child: Text(L10n.of(context).close),
              ),
            ]
          : exception == null
          ? widget.onDismiss != null
                ? [
                    AdaptiveDialogAction(
                      onPressed: () {
                        widget.onDismiss!();
                        Navigator.of(context).pop();
                      },
                      child: Text(L10n.of(context).cancel),
                    ),
                  ]
                : null
          : [
              AdaptiveDialogAction(
                onPressed: () => Navigator.of(
                  context,
                ).pop<Result<T>>(Result.error(exception, stackTrace)),
                child: Text(widget.backLabel ?? L10n.of(context).close),
              ),
            ],
      // Pangea#
    );
  }
}

extension DeprecatedApiAccessExtension<T> on Result<T> {
  T? get result => asValue?.value;

  Object? get error => asError?.error;
}
