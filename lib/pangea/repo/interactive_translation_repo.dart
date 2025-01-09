import 'dart:convert';

import 'package:http/http.dart';

import 'package:fluffychat/pangea/config/environment.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../models/custom_input_translation_model.dart';
import '../models/it_response_model.dart';
import '../models/system_choice_translation_model.dart';
import '../network/requests.dart';
import '../network/urls.dart';

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

  static Future<ITResponseModel> systemChoiceTranslate(
    SystemChoiceRequestModel subseqText,
  ) async {
    final Requests req = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );

    final Response res =
        await req.post(url: PApiUrls.subseqStep, body: subseqText.toJson());

    final decodedBody = jsonDecode(utf8.decode(res.bodyBytes).toString());

    return ITResponseModel.fromJson(decodedBody);
  }
}
