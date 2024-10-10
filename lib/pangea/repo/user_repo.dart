import 'dart:convert';

import 'package:fluffychat/pangea/constants/model_keys.dart';
import 'package:http/http.dart';

import '../models/user_profile_search_model.dart';
import '../network/requests.dart';
import '../network/urls.dart';

class PUserRepo {
  static Future<UserProfileSearchResponse> searchUserProfiles({
    // List<String>? interests,
    String? targetLanguage,
    String? sourceLanguage,
    String? country,
    // String? speaks,
    String? pageNumber,
    required String accessToken,
    required int limit,
  }) async {
    final Requests req = Requests(
      accessToken: accessToken,
    );
    final Map<String, dynamic> body = {};
    // if (interests != null) body[ModelKey.userInterests] = interests.toString();
    if (targetLanguage != null) {
      body[ModelKey.userTargetLanguage] = targetLanguage;
    }
    if (sourceLanguage != null) {
      body[ModelKey.userSourceLanguage] = sourceLanguage;
    }
    if (country != null) body[ModelKey.userCountry] = country;

    final String searchUrl =
        "${PApiUrls.searchUserProfiles}?limit=$limit${pageNumber != null ? '&page=$pageNumber' : ''}";

    final Response res = await req.post(
      url: searchUrl,
      body: body,
    );

    //PTODO - implement paginiation - make another call with next url

    return UserProfileSearchResponse.fromJson(jsonDecode(res.body));
  }
}
