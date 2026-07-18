import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

/// Regression: when the audio event's embedded `user_stt` parses to an EMPTY
/// (exhausted-fallback) model, `getSpeechToTextLocal()` must fall through to a
/// `_speechToTextRepresentation` the bot may have re-transcribed later, rather
/// than short-circuiting to null. Pre-fix, a failed transcription left NO
/// embed so the representation was checked; the R0-2 empty-parse change made
/// the empty embed PRESENT, which short-circuited and hid a recoverable
/// transcript.
///
/// The selection policy is isolated in `PangeaMessageEvent.selectUsableStt`
/// (the Matrix `Event`/`Timeline` plumbing around it has no unit harness), and
/// mirrors the bot's `_is_valid_stt_response` fall-through gate
/// (get_audio_stt.py).

SpeechToTextResponseModel _empty() =>
    SpeechToTextResponseModel(results: const []);

SpeechToTextResponseModel _withText(String text) => SpeechToTextResponseModel(
  results: [
    SpeechToTextResult(
      transcripts: [
        Transcript(
          text: text,
          confidence: 100,
          sttTokens: const [],
          langCode: 'es',
          wordsPerHr: null,
        ),
      ],
    ),
  ],
);

void main() {
  group('PangeaMessageEvent.selectUsableStt', () {
    test('empty embed falls through to a non-empty representation', () {
      final rep = _withText('hola mundo');
      final selected = PangeaMessageEvent.selectUsableStt(
        embedded: _empty(),
        representation: rep,
      );
      expect(selected, same(rep));
    });

    test('a parse-error (null) embed falls through to the representation', () {
      final rep = _withText('recovered');
      final selected = PangeaMessageEvent.selectUsableStt(
        embedded: null,
        representation: rep,
      );
      expect(selected, same(rep));
    });

    test('a non-empty embed wins even when a representation exists', () {
      final embed = _withText('embedded');
      final selected = PangeaMessageEvent.selectUsableStt(
        embedded: embed,
        representation: _withText('representation'),
      );
      expect(selected, same(embed));
    });

    test('empty embed with no representation returns null', () {
      expect(
        PangeaMessageEvent.selectUsableStt(
          embedded: _empty(),
          representation: null,
        ),
        isNull,
      );
    });

    test('empty embed with an empty representation returns null', () {
      expect(
        PangeaMessageEvent.selectUsableStt(
          embedded: _empty(),
          representation: _empty(),
        ),
        isNull,
      );
    });
  });
}
