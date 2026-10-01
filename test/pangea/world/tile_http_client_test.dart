import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';

import 'package:fluffychat/routes/world/tile_http_client.dart';

/// flutter_test's binding stubs every dart:io `HttpClient` to answer 400
/// without touching the network; this restores the real one, for the loopback
/// server below. Clients must be created inside the override's zone.
class _RealNetwork extends HttpOverrides {}

/// A server that drops every connection right after the request arrives: a
/// clean FIN before any response byte, which is what a network that went
/// away under an idle keep-alive socket looks like to dart:io.
Future<ServerSocket> _droppingServer() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) => socket.listen((_) => socket.close()));
  return server;
}

/// Resolves one tile through [provider] against the server on [port] the way
/// `TileImage.load` does, and returns how flutter_map ended it: the decoded
/// [ImageInfo], or the error it reported.
Future<Object> _loadTile(TileProvider provider, int port) {
  final image = provider.getImageWithCancelLoadingSupport(
    const TileCoordinates(0, 0, 0),
    TileLayer(urlTemplate: 'http://127.0.0.1:$port/{z}/{x}/{y}.png'),
    Completer<void>().future,
  );
  final outcome = Completer<Object>();
  image
      .resolve(ImageConfiguration.empty)
      .addListener(
        ImageStreamListener(
          (info, _) => outcome.complete(info),
          onError: (error, _) => outcome.complete(error),
        ),
      );
  return outcome.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final uri = Uri.parse('https://tile.example/0/0/0.png');

  // #8844 — on iOS and Android a tile that failed while offline stayed a hole
  // after the network came back, even though #8850 retries failed tiles in
  // place: dart:io reports the drop as "Connection closed …", and flutter_map
  // reads any `closed` in a ClientException as its own client being disposed,
  // so the tile completed as a transparent success and never counted as
  // failed. The wrapper client keeps that failure an error.
  group('TileHttpClient (#8844)', () {
    test(
      'through NetworkTileProvider, a dropped connection is an error tile '
      '(where flutter_map alone paints a transparent success)',
      () => HttpOverrides.runWithHttpOverrides(() async {
        final server = await _droppingServer();
        addTearDown(server.close);

        final silenced = await _loadTile(
          NetworkTileProvider(
            cachingProvider: const DisabledMapCachingProvider(),
          ),
          server.port,
        );
        expect(
          silenced,
          isA<ImageInfo>().having(
            (info) => info.image.width,
            'width',
            1,
            // TileProvider.transparentImage is 1x1. If this stops holding,
            // flutter_map has fixed the silencing upstream and the wrapper
            // can go.
          ),
          reason: 'flutter_map takes "closed" for its own disposed client',
        );

        final client = TileHttpClient();
        addTearDown(client.close);
        final surfaced = await _loadTile(
          NetworkTileProvider(
            httpClient: client,
            cachingProvider: const DisabledMapCachingProvider(),
          ),
          server.port,
        );
        expect(
          surfaced,
          isA<TileConnectionException>().having(
            (e) => e.cause.message,
            'cause.message',
            contains('closed'),
          ),
          reason: 'the same drop must reach errorTileCallback',
        );
      }, _RealNetwork()),
    );

    test('a failure from send becomes a TileConnectionException', () async {
      final client = TileHttpClient(
        inner: MockClient(
          (_) => throw ClientException('Socket closed before request was sent'),
        ),
      );
      await expectLater(
        client.send(Request('GET', uri)),
        throwsA(
          isA<TileConnectionException>().having(
            (e) => e.toString(),
            'toString',
            'TileConnectionException: Socket closed before request was sent',
          ),
        ),
      );
    });

    test(
      'a failure in the response body becomes a TileConnectionException',
      () async {
        final client = TileHttpClient(
          inner: MockClient.streaming(
            (_, _) async => StreamedResponse(
              Stream<List<int>>.error(
                ClientException('Connection closed while receiving data'),
              ),
              200,
            ),
          ),
        );
        final response = await client.send(Request('GET', uri));
        await expectLater(
          response.stream.toBytes(),
          throwsA(isA<TileConnectionException>()),
        );
      },
    );

    test('after close, a failure passes through as the ClientException '
        'flutter_map silences', () async {
      final client = TileHttpClient(
        inner: MockClient(
          (_) => throw ClientException(
            'HTTP request failed. Client is already closed.',
          ),
        ),
      );
      client.close();
      await expectLater(
        client.send(Request('GET', uri)),
        throwsA(
          allOf(isA<ClientException>(), isNot(isA<TileConnectionException>())),
        ),
      );
    });

    test(
      'an aborted request passes through as RequestAbortedException',
      () async {
        final client = TileHttpClient(
          inner: MockClient((_) => throw RequestAbortedException(uri)),
        );
        await expectLater(
          client.send(Request('GET', uri)),
          throwsA(isA<RequestAbortedException>()),
        );
      },
    );

    test('a response passes through intact', () async {
      final client = TileHttpClient(
        inner: MockClient(
          (_) async => Response.bytes(
            const [1, 2, 3],
            200,
            headers: const {'cache-control': 'max-age=60'},
          ),
        ),
      );
      final response = await client.send(Request('GET', uri));
      expect(response.statusCode, 200);
      expect(response.headers['cache-control'], 'max-age=60');
      expect(await response.stream.toBytes(), [1, 2, 3]);
    });
  });
}
