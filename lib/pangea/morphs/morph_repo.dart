import 'dart:convert';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/morphs/morph_models.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';

import '../common/network/requests.dart';

class MorphsRepo {
  static final GetStorage _morphsStorage = GetStorage('morphs_storage');

  static void set(String languageCode, MorphsByLanguage response) {
    _morphsStorage.write(
      languageCode,
      response.toJson(),
    );
  }

  static MorphsByLanguage fromJson(Map<String, dynamic> json) {
    return MorphsByLanguage.fromJson(json);
  }

  static Future<MorphsByLanguage> get(String languageCode) async {
    final cachedJson = _morphsStorage.read(languageCode);
    if (cachedJson != null) {
      return MorphsRepo.fromJson(cachedJson);
    }

    final Requests req = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );

    final Response res = await req.get(
      url: '${PApiUrls.morphFeaturesAndTags}/$languageCode',
    );

    final decodedBody = jsonDecode(utf8.decode(res.bodyBytes));
    final response = MorphsRepo.fromJson(decodedBody);

    set(languageCode, response);

    return response;
  }
}
