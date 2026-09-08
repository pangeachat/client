// Dart imports:
import 'dart:typed_data';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix_api_lite/generated/fixed_model.dart';

// Project imports:
import 'package:fluffychat/routes/chat/calls/call_audio_download.dart';

/// A `Client` double that answers `getContent` itself and refuses every
/// other member through `noSuchMethod` -- there is no lightweight `Client`
/// fake in this SDK, and `implements Client` with every OTHER member routed
/// through `noSuchMethod` is the same shape this codebase already accepts
/// for reaching into `matrix_api_lite`'s generated types elsewhere (see
/// `lib/features/authentication/delete_account_exception.dart` and
/// siblings, which import `matrix_api_lite/generated/*` directly).
class _StubClient implements Client {
  _StubClient(this.data);

  final Uint8List data;
  String? capturedServerName;
  String? capturedMediaId;

  @override
  Future<FileResponse> getContent(
    String serverName,
    String mediaId, {
    bool? allowRemote,
    int? timeoutMs,
    bool? allowRedirect,
  }) async {
    capturedServerName = serverName;
    capturedMediaId = mediaId;
    return FileResponse(data: data, contentType: 'audio/wav');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('mxcServerAndMediaId', () {
    test('splits a plain mxc URI into its server and media id', () {
      final split = mxcServerAndMediaId(
        Uri.parse('mxc://example.com/abcDEF123'),
      );

      expect(split.serverName, 'example.com');
      expect(split.mediaId, 'abcDEF123');
    });

    test('keeps a port on the server name -- it is part of server_name', () {
      // A `:` is a legal, unescaped path-segment character (RFC 3986); a
      // server decodes the path before matching it, so `Client.getContent`
      // percent-encoding this to `%3A` round-trips back to a literal `:`
      // server-side. Dropping the port would silently address the wrong
      // origin server on any deployment that runs on a non-default port.
      final split = mxcServerAndMediaId(
        Uri.parse('mxc://example.com:8448/abcDEF123'),
      );

      expect(split.serverName, 'example.com:8448');
      expect(split.mediaId, 'abcDEF123');
    });

    test(
      'decodes a percent-escaped media id rather than double-encoding it',
      () {
        // `Client.getContent` encodes `mediaId` itself before sending it, so
        // this must hand it the DECODED id -- passing the raw (still-escaped)
        // path through would encode the `%` a second time and corrupt it.
        final split = mxcServerAndMediaId(
          Uri.parse('mxc://example.com/abc%20def'),
        );

        expect(split.mediaId, 'abc def');
      },
    );

    test(
      'refuses a non-mxc scheme rather than building a nonsense request',
      () {
        expect(
          () => mxcServerAndMediaId(Uri.parse('https://example.com/abcDEF123')),
          throwsArgumentError,
        );
      },
    );

    test('refuses an mxc URI with no host', () {
      // `mxc:/x` and `mxc:///x` both carry a non-empty PATH ('x') over an
      // EMPTY host -- checked separately from the media-id check below, or
      // an empty `serverName` would reach `Client.getContent` unnoticed.
      expect(
        () => mxcServerAndMediaId(Uri.parse('mxc:/abcDEF123')),
        throwsArgumentError,
      );
      expect(
        () => mxcServerAndMediaId(Uri.parse('mxc:///abcDEF123')),
        throwsArgumentError,
      );
    });

    test('refuses an mxc URI with no media id', () {
      expect(
        () => mxcServerAndMediaId(Uri.parse('mxc://example.com')),
        throwsArgumentError,
      );
      expect(
        () => mxcServerAndMediaId(Uri.parse('mxc://example.com/')),
        throwsArgumentError,
      );
    });

    test('refuses a media path of more than one segment', () {
      // A Matrix media id is always a single opaque token; a nested path is
      // not a media id this reader knows how to use.
      expect(
        () => mxcServerAndMediaId(Uri.parse('mxc://example.com/a/b')),
        throwsArgumentError,
      );
    });

    test('refuses a double-slash path rather than joining it into a '
        'non-empty-looking media id', () {
      // `mxc://example.com//` parses to TWO empty path segments -- joined
      // with '/', that would read as the non-empty string '/' and slip past
      // an emptiness check performed only AFTER joining. Requiring exactly
      // one non-empty segment catches this the same way it catches any
      // other multi-segment path.
      expect(
        () => mxcServerAndMediaId(Uri.parse('mxc://example.com//')),
        throwsArgumentError,
      );
    });
  });

  group('callAudioDownloaderFor', () {
    test('forwards the split server/media id and returns the bytes', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final client = _StubClient(bytes);
      final downloader = callAudioDownloaderFor(client);

      final result = await downloader(
        Uri.parse('mxc://example.com:8448/abcDEF123'),
      );

      expect(result, bytes);
      expect(client.capturedServerName, 'example.com:8448');
      expect(client.capturedMediaId, 'abcDEF123');
    });
  });
}
