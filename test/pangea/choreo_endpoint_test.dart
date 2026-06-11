import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/pangea/authentication/p_login.dart';
import 'package:fluffychat/pangea/authentication/store_login_method_repo.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/events/repo/token_api_models.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:integration_test/common.dart' hide Response;
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart';
import 'package:http/src/response.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../integration_test/users.dart';

void main() async {
  String authToken = "";
  String apiKey = "e6fa9fa97031ba0c852efe78457922f278a2fbc109752fe18e465337699e9873";

  setUpAll(() {
    return Future(() async {
      // Send login request
      String url = "https://matrix.staging.pangea.chat/_matrix/client/v3/login";

      final Map<String, dynamic> reqJSON = {
        "identifier": {
          "type": "m.id.user",
          "user": "anotheraccount", // playwright todo
        },
        "password": "aaaaaa", // playwright todo
        "type": "m.login.password",
      };

      final Response res = await Requests().post(url: url, body: reqJSON);

      // Save received access token
      final Map<String, dynamic> json = jsonDecode(
        utf8.decode(res.bodyBytes).toString(),
      );

      authToken += json["access_token"];
    });
  });

  test("Other test", () async {
    debugPrint("a1 " + apiKey);
    debugPrint("a2 " + authToken);
  });

  test("Tokenize endpoint test", () async {
    try {
    // Retrieve mock request json
    final filePath = 'lib/pangea/tokens/mock_tokenize_request.json';
    final mockFile = await File(filePath).readAsString();
    debugPrint("a2 $mockFile");
    final Map<String, dynamic> reqJSON = jsonDecode(mockFile);

    // Send mock request
    String url = "https://api.staging.pangea.chat/choreo/tokenize";

    Request req = Request('post', Uri.parse(url));

    req.headers["Authorization"] = authToken;
    req.headers["api_key"] = apiKey;

    // playwright todo
    
    final Response res = await req.post(url: url, body: reqJSON);


    // final Requests req = Requests(
    //   accessToken: authToken,
    //   choreoApiKey: apiKey,
    // );
    // final Response res = await req.post(url: PApiUrls.tokenize, body: reqJSON);

    // // Assert that received response is valid
    //   final Map<String, dynamic> json = jsonDecode(
    //     utf8.decode(res.bodyBytes).toString(),
    //   );
    //   assert(res.statusCode == 200);
    //   TokensResponseModel.fromJson(json);
    } catch (_) {
      throw Exception();
    }
  });
}
