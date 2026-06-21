import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/src/response.dart';

import 'package:fluffychat/features/activity_sessions/activity_feedback_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_feedback_response.dart';
import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_request_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_request.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_request.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/igc_request_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/igc_response_model.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/pt_v2_models.dart';
import 'package:fluffychat/routes/chat/events/repo/language_detection_request.dart';
import 'package:fluffychat/routes/chat/events/repo/language_detection_response.dart';
import 'package:fluffychat/routes/chat/events/repo/token_api_models.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/audio_encoding_enum.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_request_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/text_to_speech_request_model.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/text_to_speech_response_model.dart';
import 'package:fluffychat/routes/chat/events/token_info_feedback/token_info_feedback_request.dart';
import 'package:fluffychat/routes/chat/events/token_info_feedback/token_info_feedback_response.dart';
import 'package:fluffychat/routes/chat/events/translation/full_text_translation_request_model.dart';
import 'package:fluffychat/routes/chat/events/translation/full_text_translation_response_model.dart';
import 'package:fluffychat/routes/onboarding/custom_course_request_model.dart';
import 'package:fluffychat/routes/onboarding/custom_course_response_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'endpoint_test_env.dart';

void main() {
  String authToken = "";
  String userID = "";
  // Resolved in setUpAll from the shared endpoint-test env (the .env layer), so
  // this test points at the same environment as the synapse/cms endpoint tests.
  late String apiKey;
  late String choreoApi;

  setUpAll(() {
    return Future(() async {
      EndpointTestEnv.load();
      assert(EndpointTestEnv.testUsername != null);
      assert(EndpointTestEnv.testPassword != null);
      apiKey = EndpointTestEnv.choreoApiKey;
      choreoApi = "${EndpointTestEnv.choreoApi}/choreo";

      // Send login request
      final loginUrl = "${EndpointTestEnv.synapseUrl}/_matrix/client/v3/login";

      final Map<String, dynamic> reqJSON = {
        "identifier": {
          "type": "m.id.user",
          "user": EndpointTestEnv.testUsername,
        },
        "password": EndpointTestEnv.testPassword,
        "type": "m.login.password",
      };

      final Response res = await Requests().post(url: loginUrl, body: reqJSON);

      // Save received access token
      final Map<String, dynamic> json = jsonDecode(
        utf8.decode(res.bodyBytes).toString(),
      );

      assert(json["access_token"] != null);
      assert(json["user_id"] != null);
      authToken = json["access_token"];
      userID = json["user_id"];
    });
  });

  group("Choreo endpoint tests", () {
    test("Tokenize endpoint test", () async {
      // Send mock request
      final Map<String, dynamic> request = TokensRequestModel(
        fullText: "message",
        senderL1: "en",
        senderL2: "es",
        mock: true,
      ).toJson();
      final Requests req = Requests(
        choreoApiKey: apiKey,
        accessToken: authToken,
      );
      final Response res = await req.post(
        url: "$choreoApi/tokenize",
        body: request,
      );

      assert(res.statusCode == 200);
      final json = jsonDecode(utf8.decode(res.bodyBytes).toString());
      TokensResponseModel.fromJson(json);
    });

    test("Language detection endpoint test", () async {
      // Send mock request
      final Map<String, dynamic> request = LanguageDetectionRequest(
        text: 'text',
        senderl1: 'en',
        senderl2: 'es',
        mock: true,
      ).toJson();

      final Requests req = Requests(
        choreoApiKey: apiKey,
        accessToken: authToken,
      );
      final Response res = await req.post(
        url: "$choreoApi/language_detection",
        body: request,
      );

      // Ensure mock response is valid and compatible with response model
      assert(res.statusCode == 200);
      final json = jsonDecode(utf8.decode(res.bodyBytes).toString());
      LanguageDetectionResponse.fromJson(json);
    });

    test("Grammar correction endpoint test", () async {
      try {
        // Send mock request
        final Map<String, dynamic> request = IGCRequestModel(
          fullText: 'llamo',
          enableIGC: true,
          enableIT: true,
          userId: userID,
          prevMessages: [],
          mock: true,
          cefr: 'a1',
          l1: 'en',
          l2: 'es',
        ).toJson();

        final Requests req = Requests(
          choreoApiKey: apiKey,
          accessToken: authToken,
        );
        final Response res = await req.post(
          url: "$choreoApi/grammar_v2",
          body: request,
        );

        // Ensure mock response is valid and compatible with response model
        assert(res.statusCode == 200);
        final json = jsonDecode(utf8.decode(res.bodyBytes).toString());
        IGCResponseModel.fromJson(json);
      } catch (e) {
        throw Exception(e.toString());
      }
    });

    test("Direct translation endpoint test", () async {
      // Send mock request
      final Map<String, dynamic> request = FullTextTranslationRequestModel(
        text: 'por favor',
        tgtLang: 'en',
        userL1: 'en',
        userL2: 'es',
        mock: true,
      ).toJson();

      final Requests req = Requests(
        choreoApiKey: apiKey,
        accessToken: authToken,
      );
      final Response res = await req.post(
        url: "$choreoApi/translation/direct",
        body: request,
      );

      // Ensure mock response is valid and compatible with response model
      assert(res.statusCode == 200);
      final json = jsonDecode(utf8.decode(res.bodyBytes).toString());
      FullTextTranslationResponseModel.fromJson(json);
    });

    test("Text to speech endpoint test", () async {
      // Send mock request
      final Map<String, dynamic> request = TextToSpeechRequestModel(
        text: '',
        langCode: '',
        userL1: '',
        userL2: '',
        tokens: [],
        mock: true,
      ).toJson();

      final Requests req = Requests(
        choreoApiKey: apiKey,
        accessToken: authToken,
      );
      final Response res = await req.post(
        url: "$choreoApi/text_to_speech",
        body: request,
      );

      // Ensure mock response is valid and compatible with response model
      assert(res.statusCode == 200);
      final json = jsonDecode(utf8.decode(res.bodyBytes).toString());
      TextToSpeechResponseModel.fromJson(json);
    });

    test("Speech to text endpoint test", () async {
      // Send mock request
      final Map<String, dynamic> request = SpeechToTextRequestModel(
        audioContent: Uint8List(1),
        config: SpeechToTextAudioConfigModel(
          encoding: AudioEncodingEnum.amr,
          userL1: 'en',
          userL2: 'es',
        ),
        mock: true,
      ).toJson();

      final Requests req = Requests(
        choreoApiKey: apiKey,
        accessToken: authToken,
      );
      final Response res = await req.post(
        url: "$choreoApi/speech_to_text",
        body: request,
      );

      // Ensure mock response is valid and compatible with response model
      assert(res.statusCode == 200);
      final json = jsonDecode(utf8.decode(res.bodyBytes).toString());
      SpeechToTextResponseModel.fromJson(json);
    });

    test("Phonetic transcription endpoint test", () async {
      // Send mock request
      final Map<String, dynamic> request = PTRequest(
        surface: '行',
        langCode: 'zh',
        userL1: 'en',
        userL2: 'zh',
        mock: true,
      ).toJson();

      final Requests req = Requests(
        choreoApiKey: apiKey,
        accessToken: authToken,
      );
      final Response res = await req.post(
        url: "$choreoApi/phonetic_transcription_v2",
        body: request,
      );

      // Ensure mock response is valid and compatible with response model
      assert(res.statusCode == 200);
      final json = jsonDecode(utf8.decode(res.bodyBytes).toString());
      PTResponse.fromJson(json);
    });

    test("Lemma dictionary endpoint test", () async {
      // Send mock request
      final Map<String, dynamic> request = LemmaInfoRequest(
        lemma: 'ahora',
        userL1: 'en',
        lemmaLang: 'es',
        partOfSpeech: 'adv',
        messageInfo: {},
        mock: true,
      ).toJson();

      final Requests req = Requests(
        choreoApiKey: apiKey,
        accessToken: authToken,
      );
      final Response res = await req.post(
        url: "$choreoApi/lemma_definition",
        body: request,
      );

      // Ensure mock response is valid and compatible with response model
      assert(res.statusCode == 200);
      final json = jsonDecode(utf8.decode(res.bodyBytes).toString());
      LemmaInfoResponse.fromJson(json);
    });

    test("Activity summary endpoint test", () async {
      // Send mock request
      final Map<String, dynamic> request = ActivitySummaryRequestModel(
        activity: ActivityPlanModel(
          req: ActivityPlanRequest(
            topic: '',
            mode: '',
            objective: '',
            media: MediaEnum.nan,
            cefrLevel: LanguageLevelTypeEnum.a2,
            languageOfInstructions: 'en',
            targetLanguage: 'es',
            numberOfParticipants: 2,
          ),
          title: '',
          learningObjective: '',
          instructions: '',
          vocab: [],
          activityId: '',
        ),
        activityResults: [],
        contentFeedback: [],
        mock: true,
      ).toJson();

      final Requests req = Requests(
        choreoApiKey: apiKey,
        accessToken: authToken,
      );
      final Response res = await req.post(
        url: "$choreoApi/activity_summary",
        body: request,
      );

      // Ensure mock response is valid and compatible with response model
      assert(res.statusCode == 200);
      final json = jsonDecode(utf8.decode(res.bodyBytes).toString());
      ActivitySummaryResponseModel.fromJson(json);
    });

    test("Activity feedback endpoint test", () async {
      // This endpoint fetches the activity from CMS before the LLM call, so it
      // needs a real activity id in the target environment (mock=true replaces
      // only the LLM call, not the CMS fetch). Set TEST_ACTIVITY_ID in .env.
      final activityId = EndpointTestEnv.testActivityId;
      if (activityId == null) {
        markTestSkipped('Set TEST_ACTIVITY_ID to a course-plan-activity id');
        return;
      }
      // Send mock request
      final Map<String, dynamic> request = ActivityFeedbackRequest(
        activityId: activityId,
        feedbackText: "test",
        userId: userID,
        userL1: "en",
        userL2: "es",
        mock: true,
      ).toJson();

      final Requests req = Requests(
        choreoApiKey: apiKey,
        accessToken: authToken,
      );
      final Response res = await req.post(
        url: "$choreoApi/activity_plan/feedback",
        body: request,
      );

      // Ensure mock response is valid and compatible with response model
      assert(res.statusCode == 200);
      final json = jsonDecode(utf8.decode(res.bodyBytes).toString());
      ActivityFeedbackResponse.fromJson(json);
    });

    test("Token feedback endpoint test", () async {
      // Send mock request
      final Map<String, dynamic> request = TokenInfoFeedbackRequest(
        data: TokenInfoFeedbackRequestData(
          userId: userID,
          detectedLanguage: "es",
          tokens: [],
          selectedToken: 0,
          lemmaInfo: LemmaInfoResponse(emoji: [], meaning: ""),
          wordCardL1: "",
        ),
        userFeedback: "",
        mock: true,
      ).toJson();

      final Requests req = Requests(
        choreoApiKey: apiKey,
        accessToken: authToken,
      );
      final Response res = await req.post(
        url: "$choreoApi/token/feedback_v2",
        body: request,
      );

      // Ensure mock response is valid and compatible with response model
      assert(res.statusCode == 200);
      final json = jsonDecode(utf8.decode(res.bodyBytes).toString());
      TokenInfoFeedbackResponse.fromJson(json);
    });

    test("Grammar construct endpoint test", () async {
      // Send mock request
      final Map<String, dynamic> request = GrammarConstructsRequest(
        targetLanguage: "es",
        userL1: "en",
        mock: true,
      ).toJson();

      final Requests req = Requests(
        choreoApiKey: apiKey,
        accessToken: authToken,
      );
      final Response res = await req.post(
        url: "$choreoApi/grammar_constructs",
        body: request,
      );

      // Ensure mock response is valid and compatible with response model
      assert(res.statusCode == 200);
      final json = jsonDecode(utf8.decode(res.bodyBytes).toString());
      GrammarConstructsResponse.fromJson(json);
    });

    test("Custom course endpoint test", () async {
      // Send mock request
      final Map<String, dynamic> request = CustomCourseRequestModel(
        name: "test",
        languagePair: "English -> Spanish",
        languageLevel: LanguageLevelTypeEnum.a1,
        institution: "school",
        goals: "test",
        mock: true,
      ).toJson();

      final Requests req = Requests(
        choreoApiKey: apiKey,
        accessToken: authToken,
      );
      final Response res = await req.post(
        url: "$choreoApi/courses/request",
        body: request,
      );

      // Ensure mock response is valid and compatible with response model
      assert(res.statusCode == 200);
      final json = jsonDecode(utf8.decode(res.bodyBytes).toString());
      CustomCourseResponseModel.fromJson(json);
    });
  });
}
