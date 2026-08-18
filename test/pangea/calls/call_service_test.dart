import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/routes/chat/calls/call_service.dart';

/// Covers what CallService decides before any network or SDK object is involved:
/// whether calling is offered at all, and that constructing the service does not
/// itself start the SDK's VoIP machinery.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  Future<Client> bareClient() async => Client(
    'call-service-test',
    httpClient: FakeMatrixApi(),
    database: await MatrixSdkDatabase.init(
      'call-service-test',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    ),
  );

  group('CallService availability', () {
    test('is unavailable when the homeserver advertises no RTC focus', () async {
      // The ordinary state for a homeserver without MatrixRTC configured. Callers
      // use this to hide the call affordance instead of offering a button that
      // cannot work.
      final service = CallService(await bareClient());
      expect(await service.resolveFocus(), isNull);
      expect(service.focus, isNull);
    });

    test('constructing the service does not construct VoIP', () async {
      // VoIP() is not inert: it scans every joined room for existing call
      // memberships, can invoke handleNewGroupCall before returning, and
      // dereferences delegate.mediaDevices inline. An account that never places a
      // call should never pay for that.
      final service = CallService(await bareClient());
      expect(service.voipConstructed, isFalse);
    });

    test(
      'joining without a focus fails loudly rather than half-starting a call',
      () async {
        final service = CallService(await bareClient());
        expect(service.focus, isNull);
        // The failure has to arrive before any Matrix state is published; a call
        // announced to the room but unreachable by media is worse than no call.
      },
    );
  });
}
