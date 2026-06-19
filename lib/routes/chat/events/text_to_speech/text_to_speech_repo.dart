import 'package:http/http.dart' show Response;

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/text_to_speech_request_model.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/text_to_speech_response_model.dart';

/// In-memory cached text-to-speech (`POST /text_to_speech`).
/// `persist: false` — short-lived per-message audio isn't worth keeping across
/// restarts.
class TextToSpeechRepo
    extends BaseRepo<TextToSpeechRequestModel, TextToSpeechResponseModel> {
  TextToSpeechRepo._internal()
    : super(
        boxName: 'text_to_speech',
        responseFromJson: TextToSpeechResponseModel.fromJson,
        cacheDuration: const Duration(minutes: 10),
        persist: false,
      );

  static final TextToSpeechRepo _instance = TextToSpeechRepo._internal();
  static TextToSpeechRepo get instance => _instance;

  @override
  Future<Response> fetch(Requests req, TextToSpeechRequestModel request) =>
      req.post(url: PApiUrls.textToSpeech, body: request.toJson());
}
