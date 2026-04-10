import 'dart:convert';

import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix_api_lite/generated/api.dart';
import 'package:matrix/matrix_api_lite/generated/model.dart';

extension RequestTokenExtension on Api {
  /// Same as ```requestTokenToRegisterEmail```, custom module
  /// endpoint prevents sending email to already-registered emails
  Future<RequestTokenResponse> requestTokenToRegister(
    String clientSecret,
    String email,
    String username,
    int sendAttempt, {
    Uri? nextLink,
    String? idAccessToken,
    String? idServer,
  }) async {
    final requestUri = Uri(
      path: '_synapse/client/pangea/v1/register/email/requestToken',
    );
    final request = Request('POST', baseUri!.resolveUri(requestUri));
    request.headers['content-type'] = 'application/json';
    request.bodyBytes = utf8.encode(
      jsonEncode({
        'client_secret': clientSecret,
        'email': email,
        'username': username,
        if (nextLink != null) 'next_link': nextLink.toString(),
        'send_attempt': sendAttempt,
        'id_access_token': ?idAccessToken,
        'id_server': ?idServer,
      }),
    );
    final response = await httpClient.send(request);
    final responseBody = await response.stream.toBytes();
    if (response.statusCode != 200) unexpectedResponse(response, responseBody);
    final responseString = utf8.decode(responseBody);
    final json = jsonDecode(responseString);
    return RequestTokenResponse.fromJson(json as Map<String, Object?>);
  }
}
