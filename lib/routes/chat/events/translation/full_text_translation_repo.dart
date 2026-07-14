import 'package:http/http.dart' show Response;

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';
import 'package:fluffychat/routes/chat/events/translation/full_text_translation_request_model.dart';
import 'package:fluffychat/routes/chat/events/translation/full_text_translation_response_model.dart';

/// In-memory cached full-text translation (`POST /simple_translation`).
/// `persist: false` — short-lived per-message translations aren't worth keeping
/// across restarts.
class FullTextTranslationRepo
    extends
        BaseRepo<
          FullTextTranslationRequestModel,
          FullTextTranslationResponseModel
        > {
  FullTextTranslationRepo._internal()
    : super(
        cache: MemoryRepoCache<FullTextTranslationResponseModel>(),
        responseFromJson: FullTextTranslationResponseModel.fromJson,
        cacheDuration: const Duration(minutes: 10),
      );

  static final FullTextTranslationRepo _instance =
      FullTextTranslationRepo._internal();
  static FullTextTranslationRepo get instance => _instance;

  @override
  Future<Response> fetch(
    Requests req,
    FullTextTranslationRequestModel request,
  ) => req.post(url: PApiUrls.simpleTranslation, body: request.toJson());
}
