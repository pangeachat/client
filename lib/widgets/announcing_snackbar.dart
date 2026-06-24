import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// WCAG 4.1.3 (Status Messages): a SnackBar is shown visually but is silent to
/// screen readers, so status, success, and error toasts are never heard. This
/// wraps [ScaffoldMessengerState.showSnackBar] to also announce the message as a
/// live-region update via [SemanticsService.sendAnnouncement] — it moves no focus
/// and is invisible to sighted users, so there is no downside for them.
///
/// Announce politely by default; pass `assertive: true` for errors so they
/// interrupt. Pass an explicit [announcement] when the SnackBar content is not
/// simple text. See issue #7203.
extension AnnouncingScaffoldMessenger on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
  showSnackBarAnnounced(
    SnackBar snackBar, {
    String? announcement,
    bool assertive = false,
  }) {
    final controller = showSnackBar(snackBar);
    final message = announcement ?? snackBarAnnouncementText(snackBar.content);
    if (message != null && message.trim().isNotEmpty) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.maybeOf(context) ?? TextDirection.ltr,
        assertiveness: assertive
            ? Assertiveness.assertive
            : Assertiveness.polite,
      );
    }
    return controller;
  }
}

/// Best-effort plain text of a SnackBar's [content] for a screen-reader
/// announcement. Returns null when the content is not simple text, in which case
/// the caller should pass an explicit `announcement`.
String? snackBarAnnouncementText(Widget content) {
  if (content is Text) {
    return content.data ?? content.textSpan?.toPlainText();
  }
  if (content is RichText) {
    return content.text.toPlainText();
  }
  return null;
}
