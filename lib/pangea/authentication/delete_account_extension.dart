import 'dart:convert';

import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix_api_lite/generated/api.dart';

import 'package:fluffychat/pangea/authentication/delete_account_action_enum.dart';
import 'package:fluffychat/pangea/authentication/delete_account_exception.dart';
import 'package:fluffychat/pangea/authentication/delete_account_response_model.dart';

extension DeleteAccountExtension on Api {
  Future<DeleteAccountResponseModel> deleteAccount({
    DeleteAccountAction? action,
    String? userId,
  }) async {
    final requestUri = Uri(path: '_synapse/client/pangea/v1/delete_user');
    final request = Request('POST', baseUri!.resolveUri(requestUri));
    request.headers['content-type'] = 'application/json';
    request.headers['authorization'] = 'Bearer ${bearerToken!}';
    request.bodyBytes = utf8.encode(
      jsonEncode({
        if (action != null) 'action': action.name,
        'user_id': ?userId,
      }),
    );
    final response = await httpClient.send(request);
    final responseBody = await response.stream.toBytes();
    final responseString = utf8.decode(responseBody);
    final json = jsonDecode(responseString);
    if (response.statusCode != 200) throw DeleteAccountException(json);
    return DeleteAccountResponseModel.fromJson(json as Map<String, Object?>);
  }
}
