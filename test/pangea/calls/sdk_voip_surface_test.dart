// Pins the matrix-dart-sdk VoIP surface that MatrixRTC/LiveKit calling depends on.
//
// The SDK is a git dependency pinned by ref, and its VoIP tree is unmodified upstream.
// `flutter analyze` cannot protect us here: nothing in the app imports VoIP yet, and the
// SDK declares `webrtc_interface: ^1.2.0` — a range wide enough that a transitive bump
// (livekit_client pulled webrtc_interface 1.3.0 -> 1.5.1) could change these types without
// any constraint being violated.
//
// If this file stops compiling, the call implementation is affected. That is the point.

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

void main() {
  group('matrix-dart-sdk VoIP surface', () {
    test('LiveKitBackend carries the focus and defaults e2ee ON', () {
      final backend = LiveKitBackend(
        livekitServiceUrl: 'http://localhost:7880',
        livekitAlias: 'test-room',
      );

      expect(backend.type, 'livekit');
      expect(backend.livekitServiceUrl, 'http://localhost:7880');
      expect(backend.livekitAlias, 'test-room');

      // Load-bearing: the SDK defaults e2eeEnabled to true. Pangea rooms are unencrypted
      // and MSC4143 forbids MatrixRTC encryption in unencrypted rooms, so v1 must pass
      // false EXPLICITLY rather than inherit this. If this expectation ever flips, the
      // explicit override in the call code becomes redundant and should be revisited.
      expect(
        backend.e2eeEnabled,
        isTrue,
        reason:
            'SDK default changed; revisit the explicit e2eeEnabled: false override',
      );
    });

    test('e2ee can be disabled explicitly, which is what v1 does', () {
      final backend = LiveKitBackend(
        livekitServiceUrl: 'http://localhost:7880',
        livekitAlias: 'test-room',
        e2eeEnabled: false,
      );
      expect(backend.e2eeEnabled, isFalse);
    });

    test('CallBackend.fromJson builds a LiveKitBackend from foci_active', () {
      // The membership event carries foci_active entries in this shape; the SDK parses
      // them back into a backend. Note it does NOT pass e2eeEnabled, so this path yields
      // the default — another reason the call code must set it deliberately.
      final backend = CallBackend.fromJson({
        'type': 'livekit',
        'livekit_service_url': 'http://localhost:7880',
        'livekit_alias': 'test-room',
      });

      expect(backend, isA<LiveKitBackend>());
      expect(backend.type, 'livekit');
    });

    test(
      'an unknown backend type is rejected rather than silently ignored',
      () {
        expect(
          () => CallBackend.fromJson({'type': 'not-a-real-backend'}),
          throwsA(isA<MatrixSDKVoipException>()),
        );
      },
    );

    test('MeshBackend still resolves (legacy 1:1 and mesh group path)', () {
      final backend = CallBackend.fromJson({'type': 'mesh'});
      expect(backend, isA<MeshBackend>());
      expect(backend.type, 'mesh');
    });

    test('a join hands back the membership event id it published', () {
      // A CALL'S WHOLE IDENTITY COMES FROM THIS RETURN VALUE. Nothing in the
      // published membership distinguishes two calls placed by one process --
      // the call id is the room, the membership id is per VoIP instance, and
      // only `expires_ts` moves, on a clock that can step backwards -- so the
      // event id the server assigns to the write is the only witness there is.
      // CallService captures it in `announce` and keys the transcript and the
      // card on it.
      //
      // Pinned HERE because nothing else would notice it going. `void` is a top
      // type in Dart, so a return narrowed back to `Future<void>` still
      // compiles at every call site that awaits it; the call would simply stop
      // having an anchor, silently, at runtime. The typed tear-offs below are
      // the assertion -- they only type-check while the ids are returned.
      Future<String?> Function({WrappedMediaStream? stream}) entering(
        GroupCallSession session,
      ) => session.enter;
      Future<String?> Function() writingMembership(GroupCallSession session) =>
          session.sendMemberStateEvent;

      expect(entering, isA<Function>());
      expect(writingMembership, isA<Function>());
    });
  });
}
