import 'dart:async';

import 'package:http/http.dart';
import 'package:http/retry.dart';

/// A tile request that failed on the learner's own connectivity, surfaced so
/// the tile errors and [TileRetryQueue] picks it up.
///
/// Deliberately not a [ClientException]: flutter_map takes any
/// [ClientException] whose message mentions `closed` or `cancel` for its own
/// client having been closed on dispose, and completes the tile as a
/// successful transparent load instead of an error. See [TileHttpClient].
class TileConnectionException implements Exception {
  final ClientException cause;

  TileConnectionException(this.cause);

  @override
  String toString() => 'TileConnectionException: ${cause.message}';
}

/// The tile provider's HTTP client (#8844): flutter_map's own default — a
/// [RetryClient] over the platform [Client] — with every connectivity failure
/// guaranteed to reach `TileLayer.errorTileCallback`.
///
/// flutter_map's `NetworkTileImageProvider` silences any [ClientException]
/// whose message contains `closed` or `cancel`, taking it for a request that
/// died because the client was closed on dispose, and completes the tile as a
/// successful transparent load. On dart:io that net also catches what a
/// network drop produces under an idle keep-alive socket — "Connection closed
/// before full header was received", "Socket closed before request was sent",
/// "Connection closed while receiving data" — so on iOS and Android a tile
/// that failed offline never errors, never reaches [TileRetryQueue], and stays
/// a hole for as long as it is on screen. Web's `fetch` fails with "Failed to
/// fetch", which is why the in-place retry (#8850) passed web QA and not iOS.
///
/// This client tells the two apart by its own state instead of by message: a
/// [ClientException] after [close] is the dispose case and passes through
/// untouched; any other one — from [send] or from the response body stream —
/// is rethrown as a [TileConnectionException], which flutter_map does not
/// recognise and so evicts and reports as an error. A
/// [RequestAbortedException] (a pruned tile's request) also passes through:
/// flutter_map handles it first, silently, as it should.
class TileHttpClient extends BaseClient {
  final Client _inner;
  bool _closed = false;

  TileHttpClient({Client? inner}) : _inner = inner ?? RetryClient(Client());

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final StreamedResponse response;
    try {
      response = await _inner.send(request);
    } on ClientException catch (error, stackTrace) {
      _rethrow(error, stackTrace);
    }
    return StreamedResponse(
      response.stream.handleError(_rethrow),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  Never _rethrow(Object error, StackTrace stackTrace) {
    if (_closed ||
        error is RequestAbortedException ||
        error is! ClientException) {
      Error.throwWithStackTrace(error, stackTrace);
    }
    Error.throwWithStackTrace(TileConnectionException(error), stackTrace);
  }

  @override
  void close() {
    _closed = true;
    _inner.close();
  }
}
