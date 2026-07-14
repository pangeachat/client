import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/user/user_constants.dart';
import 'package:fluffychat/pangea/common/models/base_request_model.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';

void main() {
  // I8 (finding #7): `Requests.post` injection is controlled ONLY by its
  // `injectUserContext` param, never by SUBS_V2_WEB. The `false` path is the
  // money-safety contract for `/checkout` + `/cancel`, whose choreo schemas are
  // `extra="forbid"` — any injected field (cefr_level / user_gender) would be a
  // 422. This test pins that opt-out sends the body verbatim.
  //
  // NOTE: the `true` path's MatrixState-fed injection (adding cefr_level /
  // user_gender from the signed-in user's settings) cannot be exercised in a
  // bare `flutter test` — bringing up a fake `MatrixState` singleton is out of
  // scope here (same limitation the repo notes in stt_transcript_tokens_test).
  // `BaseRequestModel.injectUserContext` tolerates the missing singleton, so we
  // instead pin: (a) the branch is invoked on the default/true path, (b) it
  // never strips caller-supplied context, and (c) the helper's no-overwrite +
  // singleton-absent contract directly.
  group('Requests.post injectUserContext', () {
    late List<Map<String, dynamic>> capturedBodies;
    late http.Client mockClient;

    setUp(() {
      capturedBodies = [];
      mockClient = MockClient((request) async {
        capturedBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{}', 200);
      });
    });

    test('injectUserContext:false sends the body verbatim', () async {
      final req = Requests(accessToken: 'token', client: mockClient);
      await req.post(
        url: 'https://example.test/checkout',
        body: {'planId': 'month'},
        injectUserContext: false,
      );

      expect(capturedBodies.single, {'planId': 'month'});
      expect(capturedBodies.single.containsKey(UserConstants.cefrLevel), false);
      expect(
        capturedBodies.single.containsKey(UserConstants.userGender),
        false,
      );
    });

    test(
      'injectUserContext:false never adds context even for a bare body',
      () async {
        final req = Requests(accessToken: 'token', client: mockClient);
        await req.post(
          url: 'https://example.test/cancel',
          body: {'entitlementRef': 'ent_abc'},
          injectUserContext: false,
        );

        expect(capturedBodies.single, {'entitlementRef': 'ent_abc'});
      },
    );

    test(
      'default (no arg) routes through the injector; false bypasses it',
      () async {
        // A spy injector stands in for BaseRequestModel.injectUserContext (whose
        // real MatrixState read is unavailable under flutter test) and stamps a
        // marker. This is a NON-VACUOUS proof: the marker appears ONLY when the
        // injection branch runs, so it distinguishes default==true from false.
        var injectorCalls = 0;
        Map<String, dynamic> spyInjector(Map<dynamic, dynamic> body) {
          injectorCalls++;
          return {...Map<String, dynamic>.from(body), 'injected_marker': true};
        }

        final req = Requests(
          accessToken: 'token',
          client: mockClient,
          contextInjector: spyInjector,
        );

        // No arg -> default true -> injector runs, marker added.
        await req.post(
          url: 'https://example.test/grammar',
          body: {'t': 'hola'},
        );
        expect(injectorCalls, 1);
        expect(capturedBodies.last['injected_marker'], true);
        expect(capturedBodies.last['t'], 'hola');

        // Explicit false -> injector NOT called, verbatim body.
        await req.post(
          url: 'https://example.test/checkout',
          body: {'planId': 'month'},
          injectUserContext: false,
        );
        expect(injectorCalls, 1);
        expect(capturedBodies.last, {'planId': 'month'});
        expect(capturedBodies.last.containsKey('injected_marker'), false);
      },
    );
  });

  group('BaseRequestModel.injectUserContext contract', () {
    test('returns a String-keyed copy and tolerates missing MatrixState', () {
      final result = BaseRequestModel.injectUserContext({'planId': 'year'});
      expect(result, isA<Map<String, dynamic>>());
      expect(result['planId'], 'year');
    });

    test('does not overwrite existing cefr_level / user_gender', () {
      final result = BaseRequestModel.injectUserContext({
        UserConstants.cefrLevel: 'c1',
        UserConstants.userGender: 'male',
      });
      expect(result[UserConstants.cefrLevel], 'c1');
      expect(result[UserConstants.userGender], 'male');
    });

    test('produces a new map, not an alias of the input', () {
      final input = <String, dynamic>{'planId': 'month'};
      final result = BaseRequestModel.injectUserContext(input);
      result['planId'] = 'year';
      expect(input['planId'], 'month');
    });
  });
}
