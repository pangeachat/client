import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// A debug build must still present framework errors.
///
/// `ErrorHandler`'s `FlutterError.onError` sink replaces Flutter's default
/// handler, and for a while it dropped [FlutterError.presentError] entirely:
/// in debug web (`kDebugMode` true, not mobile) the sink was a complete no-op,
/// so a rendering exception thrown on every frame produced no output anywhere
/// a developer looks (#8677). This suite runs under `flutter test` — debug,
/// non-mobile — which is exactly that environment, so it pins the debug
/// branch. The release branch (Sentry via `logError`, no presenter) cannot run
/// here; the existing sink suites cover `logError` itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the FlutterError.onError sink still presents errors in debug',
    () async {
      final presented = <FlutterErrorDetails>[];
      final originalPresenter = FlutterError.presentError;
      FlutterError.presentError = presented.add;
      addTearDown(() => FlutterError.presentError = originalPresenter);

      final details = FlutterErrorDetails(
        exception: FlutterError(
          'RenderFlex children have non-zero flex but incoming width '
          'constraints are unbounded.',
        ),
        stack: StackTrace.current,
        library: 'rendering library',
      );
      await ErrorHandler.onFlutterError(details);

      expect(
        presented.map((d) => d.exception),
        [same(details.exception)],
        reason:
            'Overriding FlutterError.onError must not drop presentError: '
            'a debug web build otherwise swallows every framework error with '
            'no console output at all (#8677).',
      );
    },
  );
}
