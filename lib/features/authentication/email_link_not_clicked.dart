import 'package:matrix/matrix.dart';

/// Synapse's 401 when a step confirms an emailed link the learner has not
/// clicked yet: "Unable to get validated threepid", errcode M_UNAUTHORIZED.
/// The password reset reaches it when "I have clicked on the link" is tapped
/// before the link is.
extension EmailLinkNotYetClicked on MatrixException {
  bool get isEmailLinkNotYetClicked =>
      error == MatrixError.M_UNAUTHORIZED &&
      errorMessage.contains('validated threepid');
}
