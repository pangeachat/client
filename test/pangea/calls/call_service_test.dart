import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/rtc_focus.dart';

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

  /// Serves `.well-known` and nothing else, so a test can tell a real lookup
  /// from a no-op. Reading a field the SDK only fills in `checkHomeserver` —
  /// which this app never calls — looked correct and discovered nothing.
  http.Client wellKnownServing(Map<String, dynamic> body) =>
      MockClient((request) async {
        if (request.url.path == '/.well-known/matrix/client') {
          return http.Response(
            jsonEncode({
              'm.homeserver': {'base_url': 'http://localhost:8008'},
              ...body,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"errcode":"M_NOT_FOUND"}', 404);
      });

  group('CallService focus discovery', () {
    test('finds the focus its homeserver advertises', () async {
      final client = await bareClient();
      client.homeserver = Uri.parse('http://localhost:8008');

      final service = CallService(
        client,
        focusDiscovery: RtcFocusDiscovery(
          httpClient: wellKnownServing({
            'org.matrix.msc4143.rtc_foci': [
              {'type': 'livekit', 'livekit_service_url': 'http://sfu:7980'},
            ],
          }),
        ),
      );
      final focus = await service.resolveFocus();

      expect(focus, isNotNull);
      expect(focus!.serviceUrl, 'http://sfu:7980');
      expect(service.focus, same(focus), reason: 'and it is remembered');
    });

    test(
      'asks the homeserver we are connected to, not the server name',
      () async {
        // The SDK's own getWellknown resolves against the server name — the
        // delegation point used to FIND a homeserver. This app is configured with
        // one and never discovers it that way, so asking the server name would
        // query a host we are not talking to.
        final asked = <Uri>[];
        final client = await bareClient();
        client.homeserver = Uri.parse('http://localhost:8008');

        await CallService(
          client,
          focusDiscovery: RtcFocusDiscovery(
            httpClient: MockClient((request) async {
              asked.add(request.url);
              return http.Response('{}', 200);
            }),
          ),
        ).resolveFocus();

        expect(asked, [
          Uri.parse('http://localhost:8008/.well-known/matrix/client'),
        ]);
      },
    );

    test('asks once, including when the answer is no', () async {
      var requests = 0;
      final client = await bareClient();
      client.homeserver = Uri.parse('http://localhost:8008');

      final service = CallService(
        client,
        focusDiscovery: RtcFocusDiscovery(
          httpClient: MockClient((_) async {
            requests++;
            return http.Response('{"errcode":"M_NOT_FOUND"}', 404);
          }),
        ),
      );
      expect(await service.resolveFocus(), isNull);
      expect(await service.resolveFocus(), isNull);
      expect(
        requests,
        1,
        reason:
            'a homeserver without MatrixRTC is a deployment fact, '
            'not something to re-ask per room opened',
      );
    });
  });

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
