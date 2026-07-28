import 'package:http/http.dart' show Response;

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_request_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

/// In-memory cached speech-to-text (`POST /speech_to_text`).
/// `persist: false` — short-lived per-message transcripts aren't worth keeping
/// across restarts.
class SpeechToTextRepo
    extends BaseRepo<SpeechToTextRequestModel, SpeechToTextResponseModel> {
  SpeechToTextRepo._internal()
    : super(
        cache: MemoryRepoCache<SpeechToTextResponseModel>(),
        responseFromJson: SpeechToTextResponseModel.fromJson,
        cacheDuration: const Duration(minutes: 10),
      );

  static final SpeechToTextRepo _instance = SpeechToTextRepo._internal();
  static SpeechToTextRepo get instance => _instance;

  @override
  Future<Response> fetch(Requests req, SpeechToTextRequestModel request) =>
      req.post(url: PApiUrls.speechToText, body: request.toJson());

  /// Never memoize an exhausted-fallback response (`results: []`, HTTP 200).
  /// It parses to a valid-but-empty model since R0-2; caching it would pin a
  /// "no transcript" answer for the full 10-minute `cacheDuration` and starve
  /// the retry the next tap would otherwise make.
  @override
  bool shouldCache(SpeechToTextResponseModel response) =>
      response.results.isNotEmpty;
}
