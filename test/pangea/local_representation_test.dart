import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/languages/language_constants.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/models/language_detection_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/representation_content_model.dart';
import 'package:fluffychat/routes/chat/events/models/tokens_event_content_model.dart';
import 'package:fluffychat/routes/chat/events/repo/language_detection_repo.dart';
import 'package:fluffychat/routes/chat/events/repo/language_detection_request.dart';
import 'package:fluffychat/routes/chat/events/repo/language_detection_response.dart';
import 'package:fluffychat/routes/chat/events/repo/token_api_models.dart';
import 'package:fluffychat/routes/chat/events/repo/tokens_repo.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/text_to_speech_repo.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/text_to_speech_request_model.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/text_to_speech_response_model.dart';
import 'package:fluffychat/routes/chat/events/translation/full_text_translation_repo.dart';
import 'package:fluffychat/routes/chat/events/translation/full_text_translation_request_model.dart';
import 'package:fluffychat/routes/chat/events/translation/full_text_translation_response_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'get_test_client.dart';
import 'sentry_capture_harness.dart';

/// #9833: a learner opens the toolbar on a message with no representation in a
/// room where they may not post one. That is a course's Announcements chat,
/// where a teacher's dashboard post arrives as plain text with no tokens. The
/// representation and its tokens are made for that learner and kept in memory;
/// nothing is posted, so the server refuses nothing and nothing reaches Sentry.
/// Where the learner can post, both are still shared with the room.

/// The one room [FakeMatrixApi] accepts posts to.
const _chatId = '!1234:fakeServer.notExisting';
const _announcementsId = '!announcements:fakeServer.notExisting';
const _teacherId = '@teacher:fakeServer.notExisting';
const _messageId = r'$announcement:fakeServer.notExisting';
const _text = 'Hola a todos';

const _spanish = [LanguageDetectionModel(langCode: 'es', confidence: 1)];

final _tokens = [_token('Hola', 0), _token('a', 5), _token('todos', 7)];

PangeaToken _token(String content, int offset) => PangeaToken.fromJson({
  'text': {'content': content, 'offset': offset, 'length': content.length},
  'lemma': {'text': content, 'save_vocab': true, 'form': content},
  'pos': 'NOUN',
  'morph': <String, dynamic>{},
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final harness = SentryCaptureHarness();
  late _Homeserver homeserver;
  late Client client;

  setUpAll(() => MatrixState.pangeaController = _Learner());

  setUp(() async {
    await harness.init();
    homeserver = _Homeserver();
    client = await getTestClient(httpClient: homeserver);

    // The choreo answers for this message, so no request leaves the test.
    await LanguageDetectionRepo.instance.setCached(
      LanguageDetectionRequest(text: _text, senderl1: 'en', senderl2: 'es'),
      LanguageDetectionResponse(detections: _spanish, fullText: _text),
    );
    await FullTextTranslationRepo.instance.setCached(
      FullTextTranslationRequestModel(
        text: _text,
        srcLang: LanguageKeys.unknownLanguage,
        tgtLang: 'es',
        userL2: 'es',
        userL1: 'en',
      ),
      FullTextTranslationResponseModel(
        translation: _text,
        translations: [_text],
        source: 'es',
      ),
    );
    await TokensRepo.instance.setCached(
      TokensRequestModel(
        fullText: _text,
        langCode: 'es',
        senderL1: 'en',
        senderL2: 'es',
      ),
      TokensResponseModel(tokens: _tokens, lang: 'es', detections: _spanish),
    );
  });

  tearDown(() async {
    await client.dispose();
    await harness.close();
  });

  Room room(String id, Map<String, dynamic> powerLevels) {
    final room = Room(id: id, client: client);
    room.setState(
      Event(
        type: EventTypes.RoomPowerLevels,
        content: powerLevels,
        stateKey: '',
        senderId: _teacherId,
        eventId: r'$powerLevels',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    client.rooms.add(room);
    return room;
  }

  Room announcementsRoom() =>
      room(_announcementsId, RoomDefaults.restrictedPowerLevelsContent);

  /// A dashboard announcement: plain text, no `tokensSent`.
  Future<PangeaMessageEvent> announcement(Room room) async {
    final timeline = await room.getTimeline();
    addTearDown(timeline.cancelSubscriptions);
    return PangeaMessageEvent(
      event: Event(
        type: EventTypes.Message,
        eventId: _messageId,
        senderId: _teacherId,
        originServerTs: DateTime.now(),
        content: {'msgtype': MessageTypes.Text, 'body': _text},
        room: room,
      ),
      timeline: timeline,
      ownMessage: false,
    );
  }

  List<String>? words(PangeaMessageEvent message) => message
      .messageDisplayRepresentation
      ?.tokens
      ?.map((t) => t.text.content)
      .toList();

  test('a learner who cannot post gets tokens from a representation kept '
      'for them, and nothing is posted or reported', () async {
    final message = await announcement(announcementsRoom());

    await harness.expectNoReport(message.requestDisplayTokens);

    expect(homeserver.posts, isEmpty);
    expect(message.messageDisplayRepresentation?.event, isNull);
    expect(message.messageDisplayLangCode, 'es');
    expect(words(message), ['Hola', 'a', 'todos']);
    // The word card reads the sent representation's tokens.
    expect(message.correctedSent?.tokens, hasLength(3));
  });

  test('a learner who cannot post keeps the tokens of a representation '
      'someone else shared without them', () async {
    final announcements = announcementsRoom();
    final message = await announcement(announcements);
    message.timeline.aggregatedEvents[_messageId] = {
      PangeaEventTypes.representation: {
        Event(
          type: PangeaEventTypes.representation,
          eventId: r'$shared:fakeServer.notExisting',
          senderId: _teacherId,
          originServerTs: DateTime.now(),
          content: {
            PangeaEventTypes.representation: PangeaRepresentation(
              langCode: 'es',
              text: _text,
              originalSent: true,
              originalWritten: false,
            ).toJson(),
          },
          room: announcements,
        ),
      },
    };

    await harness.expectNoReport(message.requestDisplayTokens);

    expect(homeserver.posts, isEmpty);
    expect(
      message.messageDisplayRepresentation?.event?.eventId,
      r'$shared:fakeServer.notExisting',
    );
    expect(words(message), ['Hola', 'a', 'todos']);
  });

  test('a learner who cannot post keeps their token correction', () async {
    final message = await announcement(announcementsRoom());

    await harness.expectNoReport(
      () => message.sendTokenCorrection(
        _text,
        PangeaMessageTokens(tokens: _tokens, detections: _spanish),
      ),
    );

    expect(homeserver.posts, isEmpty);
    expect(message.correctedSent?.content.isCorrection, isTrue);
    expect(words(message), ['Hola', 'a', 'todos']);
  });

  test('a learner who cannot post hears the message without sharing its '
      'audio', () async {
    final announcements = announcementsRoom();
    final message = await announcement(announcements);
    await TextToSpeechRepo.instance.setCached(
      TextToSpeechRequestModel(
        text: _text,
        langCode: 'es',
        userL1: 'en',
        userL2: 'es',
        tokens: const [],
      ),
      TextToSpeechResponseModel(
        audioContent: base64Encode([1, 2, 3]),
        mimeType: 'audio/mpeg',
        durationMillis: 1000,
        waveform: const [],
        fileExtension: 'mp3',
        ttsTokens: const [],
      ),
    );

    final audio = await message.requestTextToSpeech('es', null);

    expect(audio.bytes, [1, 2, 3]);
    // A file send registers its placeholder before its first await.
    expect(announcements.sendingFilePlaceholders, isEmpty);
  });

  test('no Pangea event is posted where the learner cannot post', () async {
    final announcements = announcementsRoom();

    await harness.expectNoReport(() async {
      final sent = await announcements.sendPangeaEvent(
        content: {'translation': 'Hello everyone', 'lang_code': 'en'},
        parentEventId: _messageId,
        type: PangeaEventTypes.sttTranslation,
      );
      expect(sent, isNull);
    });

    expect(homeserver.posts, isEmpty);
  });

  test('a learner who can post still shares the representation and its '
      'tokens', () async {
    final message = await announcement(
      room(_chatId, RoomDefaults.defaultPowerLevelsContent()),
    );

    await message.requestDisplayTokens();
    // The tokens post is not awaited by the toolbar.
    for (var i = 0; i < 100 && homeserver.posts.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(homeserver.posts, [
      PangeaEventTypes.representation,
      PangeaEventTypes.tokens,
    ]);
  });
}

/// Serves every request with [FakeMatrixApi], except that it refuses a post to
/// the Announcements room the way Synapse refuses a learner there. Records the
/// event type of every post either room receives.
class _Homeserver extends http.BaseClient {
  final _fake = FakeMatrixApi();
  final posts = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final path = request.url.pathSegments;
    final send = path.indexOf('send');
    if (request.method != 'PUT' || send < 1 || send + 1 >= path.length) {
      return _fake.send(request);
    }

    posts.add(path[send + 1]);
    if (path[send - 1] != _announcementsId) return _fake.send(request);

    final body = jsonEncode({
      'errcode': 'M_FORBIDDEN',
      'error':
          "You don't have permission to post that to the room. "
          'user_level (0) < send_level (50)',
    });
    return Future.value(
      http.StreamedResponse(
        Stream.value(utf8.encode(body)),
        403,
        headers: {'content-type': 'application/json'},
        request: request,
      ),
    );
  }
}

/// A learner of Spanish whose first language is English.
class _Learner implements PangeaController {
  @override
  final UserController userController = _LearnerSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _LearnerSettings implements UserController {
  @override
  final LanguageModel userL1 = LanguageModel(
    langCode: 'en',
    displayName: 'English',
  );

  @override
  final LanguageModel userL2 = LanguageModel(
    langCode: 'es',
    displayName: 'Spanish',
  );

  @override
  String get userL1Code => userL1.langCode;

  @override
  String get userL2Code => userL2.langCode;

  @override
  bool isToolEnabled(ToolSetting setting) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
