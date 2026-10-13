import 'package:http/http.dart' as http;

import 'package:fluffychat/features/network_filter/filtered_network_controller.dart';

/// Wraps the Matrix client's HTTP client so every chat server request tells
/// [FilteredNetworkController] whether it reached the server. Sync retries
/// constantly, so a blocked chat server clears as soon as the network lets
/// one through.
class FilteredNetworkObserverClient extends http.BaseClient {
  final http.Client _inner;

  FilteredNetworkObserverClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      FilteredNetworkController.instance.observe(
        request.url,
        _inner.send(request),
      );

  @override
  void close() => _inner.close();
}
