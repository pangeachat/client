import 'dart:convert';

import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix_api_lite/generated/api.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';

extension SpaceCodeExtension on Api {
  Future<String> getSpaceCode() async {
    final requestUri = Uri(
      path: '/_synapse/client/pangea/v1/request_room_code',
    );
    final request = Request('GET', baseUri!.resolveUri(requestUri));
    request.headers['content-type'] = 'application/json';
    request.headers['authorization'] = 'Bearer ${bearerToken!}';
    final response = await httpClient.send(request);
    final responseBody = await response.stream.toBytes();
    final responseString = utf8.decode(responseBody);
    if (response.statusCode != 200) {
      throw PangeaHttpException.fromStreamedResponse(
        request,
        response,
        responseBody,
      );
    }
    final json = jsonDecode(responseString);
    if (json['access_code'] is String) {
      return json['access_code'] as String;
    } else {
      throw Exception('Invalid response, access_code not found $response');
    }
  }
}

extension SpaceCodeRequest on Client {
  Future<String> requestSpaceCode() => getSpaceCode();
}
