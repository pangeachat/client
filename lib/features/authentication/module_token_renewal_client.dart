import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/authentication/token_renewal_extension.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';

/// Wraps the Matrix client's HTTP client so a call to the homeserver's Pangea
/// module first waits for an expired access token to be renewed, then goes out
/// with the renewed one (session-lifetime.instructions.md). Each module call
/// reads the token while it builds the request, before any renewal lands.
class ModuleTokenRenewalClient extends http.BaseClient {
  ModuleTokenRenewalClient(this._inner, this._matrixClient);

  final http.Client _inner;

  /// A getter, because the Matrix client is built with this as its HTTP client.
  final Client Function() _matrixClient;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (PApiUrls.isSynapseModulePath(request.url.path) &&
        request.headers.containsKey('authorization')) {
      final client = _matrixClient();
      await client.renewExpiredToken();
      final token = client.accessToken;
      if (token != null) request.headers['authorization'] = 'Bearer $token';
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
