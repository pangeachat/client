import 'dart:convert';

import 'package:http/http.dart';

import 'package:fluffychat/pangea/choreographer/repo/igc_request_model.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import '../../common/network/requests.dart';
import '../../common/network/urls.dart';
import '../models/igc_text_data_model.dart';

class IgcRepo {
  static Future<IGCTextData> getIGC(
    String? accessToken, {
    required IGCRequestModel igcRequest,
  }) async {
    final Requests req = Requests(
      accessToken: accessToken,
      choreoApiKey: Environment.choreoApiKey,
    );
    final Response res = await req.post(
      url: PApiUrls.igcLite,
      body: igcRequest.toJson(),
    );

    final Map<String, dynamic> json =
        jsonDecode(utf8.decode(res.bodyBytes).toString());

    final IGCTextData response = IGCTextData.fromJson(json);

    return response;
  }
}
