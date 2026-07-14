import 'package:http/http.dart' show Response;

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/persistent_repo_cache.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/pt_v2_models.dart';

class PTV2Repo extends BaseRepo<PTRequest, PTResponse> {
  PTV2Repo._internal()
    : super(
        cache: PersistentRepoCache<PTResponse>('phonetic_transcription_v2'),
        responseFromJson: PTResponse.fromJson,
        cacheDuration: const Duration(hours: 24),
      );

  static final PTV2Repo _instance = PTV2Repo._internal();
  static PTV2Repo get instance => _instance;

  @override
  Future<Response> fetch(Requests req, PTRequest request) =>
      req.post(url: PApiUrls.phoneticTranscriptionV2, body: request.toJson());
}
