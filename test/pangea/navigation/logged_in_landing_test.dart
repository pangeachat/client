import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/pangea/common/utils/p_vguard.dart';

/// Where a client that has just announced `LoginState.loggedIn` is sent.
///
/// The listener behind this (matrix.dart) used to send it to the world map
/// every time, which is right for a login the user just performed and wrong for
/// the same announcement made by a session merely being RESTORED at startup:
/// that one arrives after the app has already resolved the URL the user opened,
/// so the map lands on top of it and the deep link is gone.
///
/// It was a race — one cold load in ten on the local stack — so it read as
/// "opening a chat by link stopped working after a call" rather than as a
/// startup bug, and the harness's retry hid the rest.
void main() {
  group('PAuthGaurd.loggedInLanding', () {
    const deepLink = '/?left=chats,room:!abc';

    test(
      'leaves a deep link alone — the URL is the one the user asked for',
      () {
        expect(
          PAuthGaurd.loggedInLanding(
            current: Uri.parse(deepLink),
            isL2Set: true,
          ),
          isNull,
        );
      },
    );

    test('leaves the bare world map alone', () {
      expect(
        PAuthGaurd.loggedInLanding(
          current: Uri.parse(PRoutes.world),
          isL2Set: true,
        ),
        isNull,
      );
    });

    test('leaves any other in-app location alone', () {
      for (final location in const [
        '/?left=chats',
        '/?right=analytics:vocab',
        '/?left=chats,room:!abc&right=analytics:grammar',
        '/logs',
      ]) {
        expect(
          PAuthGaurd.loggedInLanding(
            current: Uri.parse(location),
            isL2Set: true,
          ),
          isNull,
          reason: location,
        );
      }
    });

    test('moves a finished account off every entry screen', () {
      for (final location in const [
        '/home',
        '/home/login',
        '/home/login/email',
        '/home/signup',
        '/home/signup/email',
        // Onboarding and registration too: an account that has already chosen
        // its language has finished with both, and being carried off them is
        // what happened before this decision existed.
        '/onboarding',
        '/registration',
      ]) {
        expect(
          PAuthGaurd.loggedInLanding(
            current: Uri.parse(location),
            isL2Set: true,
          ),
          PRoutes.world,
          reason: location,
        );
      }
    });

    test('registration outranks the location, deep link or not', () {
      for (final location in const [deepLink, '/home/login', PRoutes.world]) {
        expect(
          PAuthGaurd.loggedInLanding(
            current: Uri.parse(location),
            isL2Set: false,
          ),
          '/registration',
          reason: location,
        );
      }
    });

    test(
      'a path merely starting with the same letters is not a sign-in screen',
      () {
        // `/homework` is not under `/home`, and a prefix test that said it was
        // would throw away that URL for ever.
        for (final location in const ['/homework', '/onboardings']) {
          expect(
            PAuthGaurd.loggedInLanding(
              current: Uri.parse(location),
              isL2Set: true,
            ),
            isNull,
            reason: location,
          );
        }
      },
    );
  });
}
