import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/network_filter/network_probe.dart';
import 'package:fluffychat/features/network_filter/network_verdict.dart';

/// #9434 — one request to one host, classified by who answered.
void main() {
  final url = Uri.https('api.pangea.chat', '/choreo/version');

  Future<NetworkProbeResult> probeAnswering(http.Response response) =>
      NetworkProbe.probeWithClient(
        url,
        MockClient((request) async {
          expect(request.method, 'HEAD');
          expect(request.followRedirects, isFalse);
          return response;
        }),
      );

  Future<NetworkProbeResult> probeFailing(Object error) =>
      NetworkProbe.probeWithClient(url, MockClient((_) => throw error));

  group('NetworkProbe.probeWithClient', () {
    test('any status from the host is an answer', () async {
      expect(
        await probeAnswering(http.Response('', 200)),
        NetworkProbeResult.answered,
      );
      expect(
        await probeAnswering(http.Response('', 405)),
        NetworkProbeResult.answered,
      );
    });

    test('our own outage is an answer, never a block', () async {
      expect(
        await probeAnswering(http.Response('', 503)),
        NetworkProbeResult.answered,
      );
    });

    test(
      'a redirect off the host is a filter answering in its place',
      () async {
        final result = await probeAnswering(
          http.Response(
            '',
            302,
            headers: {'location': 'https://block.securly.com/blocked'},
          ),
        );
        expect(result, NetworkProbeResult.answeredElsewhere);
      },
    );

    test('a redirect on the same host is still the host answering', () async {
      final result = await probeAnswering(
        http.Response('', 301, headers: {'location': '/choreo/version/'}),
      );
      expect(result, NetworkProbeResult.answered);
    });

    test('a refused connection is a refusal', () async {
      expect(
        await probeFailing(http.ClientException('Connection refused', url)),
        NetworkProbeResult.refused,
      );
    });

    test(
      'a TLS failure, which package:http does not wrap, is a refusal',
      () async {
        expect(
          await probeFailing(
            const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
          ),
          NetworkProbeResult.refused,
        );
      },
    );

    test('no answer within the timeout is slow, not a block', () {
      fakeAsync((async) {
        NetworkProbeResult? result;
        NetworkProbe.probeWithClient(
          url,
          MockClient((_) => Completer<http.Response>().future),
        ).then((r) => result = r);
        async.elapse(NetworkProbe.timeout + const Duration(seconds: 1));
        expect(result, NetworkProbeResult.slow);
      });
    });
  });

  group('NetworkVerdict.of', () {
    test('a host that answered is reachable whatever the neutral host did', () {
      for (final needed in [
        NetworkProbeResult.answered,
        NetworkProbeResult.slow,
      ]) {
        expect(
          NetworkVerdict.of(needed: needed, neutralAnswered: false),
          NetworkVerdict.reachable,
        );
        expect(
          NetworkVerdict.of(needed: needed, neutralAnswered: true),
          NetworkVerdict.reachable,
        );
      }
    });

    test('a blocked host with the neutral host answering is filtered', () {
      for (final needed in [
        NetworkProbeResult.refused,
        NetworkProbeResult.answeredElsewhere,
      ]) {
        expect(
          NetworkVerdict.of(needed: needed, neutralAnswered: true),
          NetworkVerdict.filtered,
        );
      }
    });

    test('a blocked host with nothing answering is offline', () {
      expect(
        NetworkVerdict.of(
          needed: NetworkProbeResult.refused,
          neutralAnswered: false,
        ),
        NetworkVerdict.offline,
      );
    });
  });
}
