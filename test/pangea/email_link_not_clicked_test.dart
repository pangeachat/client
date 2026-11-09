import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/authentication/email_link_not_clicked.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

MatrixException _matrixError(String errcode, String message) =>
    MatrixException.fromJson({'errcode': errcode, 'error': message});

/// CLIENT-F64: the password reset's "I have clicked on the link" tapped before
/// the link was clicked. Synapse answers 401 M_UNAUTHORIZED "Unable to get
/// validated threepid"; the learner is told to click the link and Sentry is not.
void main() {
  final notClicked = _matrixError(
    'M_UNAUTHORIZED',
    'Unable to get validated threepid',
  );

  test('the unclicked-link answer is recognised', () {
    expect(notClicked.isEmailLinkNotYetClicked, isTrue);
  });

  test('another 401 is not', () {
    expect(
      _matrixError(
        'M_UNAUTHORIZED',
        'Invalid password',
      ).isEmailLinkNotYetClicked,
      isFalse,
    );
    expect(
      _matrixError(
        'M_FORBIDDEN',
        'Unable to get validated threepid',
      ).isEmailLinkNotYetClicked,
      isFalse,
    );
  });

  test('the unclicked-link answer is not reported; other 401s are', () {
    expect(ErrorHandler.shouldReport(notClicked), isFalse);
    expect(
      ErrorHandler.shouldReport(
        _matrixError('M_UNAUTHORIZED', 'Invalid password'),
      ),
      isTrue,
    );
  });
}
