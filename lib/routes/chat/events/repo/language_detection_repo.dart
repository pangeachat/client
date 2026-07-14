import 'package:http/http.dart' show Response;

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';
import 'package:fluffychat/routes/chat/events/repo/language_detection_request.dart';
import 'package:fluffychat/routes/chat/events/repo/language_detection_response.dart';

/// In-memory cached language detection (`POST /language_detection`).
/// `persist: false` — short-lived per-message detections aren't worth keeping
/// across restarts.
class LanguageDetectionRepo
    extends BaseRepo<LanguageDetectionRequest, LanguageDetectionResponse> {
  LanguageDetectionRepo._internal()
    : super(
        cache: MemoryRepoCache<LanguageDetectionResponse>(),
        responseFromJson: LanguageDetectionResponse.fromJson,
        cacheDuration: const Duration(minutes: 10),
      );

  static final LanguageDetectionRepo _instance =
      LanguageDetectionRepo._internal();
  static LanguageDetectionRepo get instance => _instance;

  @override
  Future<Response> fetch(Requests req, LanguageDetectionRequest request) =>
      req.post(url: PApiUrls.languageDetection, body: request.toJson());
}
