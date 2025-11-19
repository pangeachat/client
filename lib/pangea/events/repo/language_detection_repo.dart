import 'dart:convert';

import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/events/repo/language_detection_request.dart';
import 'package:fluffychat/pangea/events/repo/language_detection_response.dart';

class LanguageDetectionRepo {
  static Future<LanguageDetectionResponse> get(
    String? accessToken, {
    required LanguageDetectionRequest request,
  }) async {
    final Requests req = Requests(
      accessToken: accessToken,
      choreoApiKey: Environment.choreoApiKey,
    );
    final Response res = await req.post(
      url: PApiUrls.languageDetection,
      body: request.toJson(),
    );

    final Map<String, dynamic> json =
        jsonDecode(utf8.decode(res.bodyBytes).toString());

    final LanguageDetectionResponse response =
        LanguageDetectionResponse.fromJson(json);

    return response;
  }
}
