import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/streamed_stt_embed.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_partial_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_provenance.dart';
import '../get_test_client.dart';

void main() {
  late Client client;
  late Room room;
  late Timeline timeline;

  setUp(() async {
    client = await getTestClient();
    room = Room(id: '!voice:fakeServer.notExisting', client: client);
    timeline = await room.getTimeline();
  });

  tearDown(() async {
    timeline.cancelSubscriptions();
    await client.dispose();
  });

  PangeaMessageEvent audio(Map<String, dynamic>? userStt) => PangeaMessageEvent(
    event: Event(
      type: EventTypes.Message,
      eventId: r'$audioflag:fakeServer.notExisting',
      senderId: client.userID!,
      originServerTs: DateTime.now(),
      content: {
        'msgtype': 'm.audio',
        'body': 'recording.wav',
        'user_stt': ?userStt,
      },
      room: room,
    ),
    timeline: timeline,
    ownMessage: true,
  );

  test('isTranscriptEdited: true only when user_stt.edited == true', () {
    expect(audio({SttProvenanceKeys.edited: true}).isTranscriptEdited, isTrue);
  });

  test('isTranscriptEdited: false for a verbatim embed (edited == false)', () {
    expect(
      audio({
        SttProvenanceKeys.edited: false,
        'results': <dynamic>[],
      }).isTranscriptEdited,
      isFalse,
    );
  });

  test('isTranscriptEdited: false when the provenance key is absent', () {
    // A pre-provenance embed (no edited key) reads verbatim.
    expect(audio({'results': <dynamic>[]}).isTranscriptEdited, isFalse);
  });

  test('isTranscriptEdited: false when there is no user_stt embed at all', () {
    expect(audio(null).isTranscriptEdited, isFalse);
  });

  test('sttDiffPair: (original, sent) for an edited streamed send', () {
    final embed = streamedUserSttEmbed(
      const StreamingSttSendData(
        text: 'hola mundo',
        originalAsrText: 'ola mundo',
        isEdited: true,
        editDistance: 1,
        words: <SttWord>[],
        service: 'deepgram',
        langCode: 'en',
      ),
      langCode: 'en',
    );
    final pair = audio(embed).sttDiffPair;
    expect(pair, isNotNull);
    expect(pair!.originalAsr, 'ola mundo');
    expect(pair.current, 'hola mundo');
  });

  test('sttDiffPair: null for a verbatim embed', () {
    expect(audio({SttProvenanceKeys.edited: false}).sttDiffPair, isNull);
  });
}
