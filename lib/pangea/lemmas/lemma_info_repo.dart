import 'dart:convert';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_request.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/lemmas/user_set_lemma_info.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';

class LemmaInfoRepo {
  static final GetStorage _lemmaStorage = GetStorage('lemma_storage');

  static void set(LemmaInfoRequest request, LemmaInfoResponse response) {
    // set expireAt if not set
    response.expireAt ??= DateTime.now().add(const Duration(days: 100));
    _lemmaStorage.write(request.storageKey, response.toJson());
  }

  static Future<LemmaInfoResponse> get(
    LemmaInfoRequest request, [
    String? feedback,
  ]) async {
    // if the user has either emojis or meaning in the past, use those first
    final UserSetLemmaInfo? userSetLemmaInfo = request.cId.userLemmaInfo;
    if (userSetLemmaInfo?.emojis != null && userSetLemmaInfo?.meaning != null) {
      return LemmaInfoResponse(
        emoji: userSetLemmaInfo!.emojis!,
        meaning: userSetLemmaInfo.meaning!,
        expireAt: DateTime.now().add(const Duration(days: 100)),
      );
    }

    final cachedJson = _lemmaStorage.read(request.storageKey);

    final cached =
        cachedJson == null ? null : LemmaInfoResponse.fromJson(cachedJson);

    if (cached != null) {
      if (DateTime.now().isBefore(cached.expireAt!)) {
        // return cache as is if we're using expireAt and it's set but not expired
        return LemmaInfoResponse(
          emoji: userSetLemmaInfo?.emojis ?? cached.emoji,
          meaning: userSetLemmaInfo?.meaning ?? cached.meaning,
        );
      } else {
        // if it's expired, remove it
        _lemmaStorage.remove(request.storageKey);
      }
    }

    final Requests req = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );

    final Response res = await req.post(
      url: PApiUrls.lemmaDictionary,
      body: request.toJson(),
    );

    final decodedBody = jsonDecode(utf8.decode(res.bodyBytes));
    final response = LemmaInfoResponse.fromJson(decodedBody);

    set(request, response);

    return LemmaInfoResponse(
      emoji: userSetLemmaInfo?.emojis ?? response.emoji,
      meaning: userSetLemmaInfo?.meaning ?? response.meaning,
    );
  }
}
