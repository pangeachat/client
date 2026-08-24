import 'package:flutter/widgets.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';

/// An expected outcome of an email signup attempt — something the person
/// filling in the form caused, or can act on, rather than a defect.
///
/// These used to travel the error path: the homeserver's raw English string
/// ("User ID already taken.", "Rate limited") landed in the loading dialog's
/// red error state, and every one of them was captured to Sentry (#8370).
/// Classifying them keeps them off that path, so the form prints localized
/// copy and only genuine defects are reported.
enum SignupFailure {
  usernameTaken,
  rateLimited,

  /// The attempt stopped before the homeserver answered — the person navigated
  /// away, cancelling the interactive-auth flow. Control flow, not a failure
  /// anyone needs to be told about.
  abandoned;

  /// The message `UiaRequest` completes with when its flow is cancelled. The
  /// SDK throws a bare [Exception], so the text is the only thing to match on.
  static const String _cancelledUiaRequest = 'Request has been canceled';

  /// The failure [error] represents, or null when it is not an expected outcome
  /// and so must keep propagating to the error path.
  static SignupFailure? from(Object error) {
    if (error is MatrixException) {
      switch (error.error) {
        case MatrixError.M_USER_IN_USE:
          return SignupFailure.usernameTaken;
        case MatrixError.M_LIMIT_EXCEEDED:
          return SignupFailure.rateLimited;
        default:
          return null;
      }
    }
    return error.toString().contains(_cancelledUiaRequest)
        ? SignupFailure.abandoned
        : null;
  }

  /// What the form shows, or null when the person needs no message.
  String? localizedMessage(BuildContext context) => switch (this) {
    SignupFailure.usernameTaken => L10n.of(
      context,
    ).usernameTakenPleaseChooseAnother,
    SignupFailure.rateLimited => L10n.of(context).tooManyRequestsWarning,
    SignupFailure.abandoned => null,
  };
}
