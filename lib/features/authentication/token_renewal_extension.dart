import 'dart:async';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

extension TokenRenewalExtension on Client {
  /// How long a request waits for an expired access token to be renewed
  /// before going out without it (session-lifetime.instructions.md).
  static const Duration tokenRenewalWait = Duration(seconds: 10);

  /// Renews the access token when it has expired or is about to, so a request
  /// does not go out with a token the server refuses. Tokens last 24 hours, so
  /// a learner who opens the app, or brings it back from the background, after
  /// a day away holds an expired one; the SDK otherwise renews it only from its
  /// sync loop, racing every request (#9304, #9835). Requests that arrive
  /// together share one renewal. Offline the renewal cannot finish: after
  /// [wait] the caller carries on, and the SDK retries on the next sync.
  Future<void> renewExpiredToken({Duration wait = tokenRenewalWait}) async {
    if (!isLogged()) return;
    try {
      await ensureNotSoftLoggedOut().timeout(wait);
    } on TimeoutException {
      // silent-ok: offline or slow network; the SDK retries on the next sync.
      Logs().w('Token renewal took over ${wait.inSeconds}s; carrying on');
    } on MatrixException catch (e, s) {
      // The homeserver rejected the session and the SDK has signed out, so
      // the app shows the signed-out screen.
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'client_name': clientName},
        level: SentryLevel.warning,
      );
    }
  }
}
