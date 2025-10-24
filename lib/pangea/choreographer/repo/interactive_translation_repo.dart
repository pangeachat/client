import 'dart:convert';

import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../common/network/requests.dart';
import '../../common/network/urls.dart';
import 'custom_input_request_model.dart';
import 'it_response_model.dart';

class ITRepo {
  static Future<ITResponseModel> customInputTranslate(
    CustomInputRequestModel initalText,
  ) async {
    final Requests req = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );
    final Response res =
        await req.post(url: PApiUrls.firstStep, body: initalText.toJson());

    final json = jsonDecode(utf8.decode(res.bodyBytes).toString());

    return ITResponseModel.fromJson(json);
  }
}
