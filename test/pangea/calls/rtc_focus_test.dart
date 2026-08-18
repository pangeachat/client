import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/rtc_focus.dart';

DiscoveryInformation _wellKnown(Map<String, Object?> extra) =>
    DiscoveryInformation.fromJson({
      'm.homeserver': {'base_url': 'http://localhost:8008'},
      ...extra,
    });

void main() {
  group('RtcFocus.fromWellKnown', () {
    test('reads a livekit focus a homeserver advertises', () {
      final focus = RtcFocus.fromWellKnown(
        _wellKnown({
          RtcFocus.wellKnownKey: [
            {'type': 'livekit', 'livekit_service_url': 'http://localhost:7980'},
          ],
        }),
      );
      expect(focus?.serviceUrl, 'http://localhost:7980');
    });

    test('picks the livekit entry when other focus types are present', () {
      final focus = RtcFocus.fromWellKnown(
        _wellKnown({
          RtcFocus.wellKnownKey: [
            {'type': 'something-else', 'url': 'http://nope'},
            {'type': 'livekit', 'livekit_service_url': 'http://localhost:7980'},
          ],
        }),
      );
      expect(focus?.serviceUrl, 'http://localhost:7980');
    });

    // A homeserver with no MatrixRTC configured is an ordinary state, not an error.
    // Returning null lets the caller decide between hiding the call button and
    // falling back to configuration; throwing would force every caller to catch.
    test('returns null when no focus is advertised', () {
      expect(RtcFocus.fromWellKnown(_wellKnown({})), isNull);
      expect(RtcFocus.fromWellKnown(null), isNull);
    });

    test(
      'returns null on malformed or empty entries rather than half-parsing',
      () {
        expect(
          RtcFocus.fromWellKnown(
            _wellKnown({RtcFocus.wellKnownKey: 'not-a-list'}),
          ),
          isNull,
        );
        expect(
          RtcFocus.fromWellKnown(
            _wellKnown({
              RtcFocus.wellKnownKey: [
                {'type': 'livekit', 'livekit_service_url': ''},
              ],
            }),
          ),
          isNull,
        );
      },
    );
  });

  group('RtcFocus.backendForRoom', () {
    test('disables e2ee explicitly instead of inheriting the SDK default', () {
      final backend = const RtcFocus(
        serviceUrl: 'http://localhost:7980',
      ).backendForRoom('!room:pangea.localhost');

      // The SDK defaults this to true. Pangea rooms are unencrypted and MSC4143
      // forbids MatrixRTC encryption there, so inheriting would produce a call
      // encrypted in name only, against a plaintext room.
      expect(backend.e2eeEnabled, isFalse);
      expect(backend.livekitServiceUrl, 'http://localhost:7980');
      expect(backend.livekitAlias, '!room:pangea.localhost');
      expect(backend.type, 'livekit');
    });
  });
}
