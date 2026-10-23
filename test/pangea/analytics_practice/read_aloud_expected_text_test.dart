import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/analytics/construct_analytics/practice/read_aloud_recorder.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_request_model.dart';

/// The sentence a read-aloud item asks for travels as the choreographer's
/// `expected_text` hint on both transcription routes. See
/// practice-exercises.instructions.md, "Speaking practice", Transcription.
void main() {
  SpeechToTextRequestModel request(String? hint) => buildVoiceSttRequest(
    audioContent: Uint8List(44),
    mimeType: 'audio/wav',
    userL1: 'en',
    userL2: 'es',
    expectedText: hint,
  );

  test(
    'the batch request carries the hint, trimmed, and omits a blank one',
    () {
      expect(
        request(' ¿Cuándo debemos irnos? ').toJson()['expected_text'],
        '¿Cuándo debemos irnos?',
      );
      expect(request('   ').toJson().containsKey('expected_text'), isFalse);
      expect(request(null).toJson().containsKey('expected_text'), isFalse);
    },
  );

  test('a hinted request is its own cache slot', () {
    final hinted = request('hola');
    final plain = request(null);
    expect(hinted, isNot(equals(plain)));
    expect(hinted.storageKey, isNot(equals(plain.storageKey)));
    expect(request('hola').storageKey, hinted.storageKey);
  });

  test('the relay URL carries the practice tag and the hint, encoded', () {
    final url = readAloudRelayUrl(
      'wss://api.example/choreo/speech_to_text/stream?wire=2',
      expectedText: '¿Cuándo debemos irnos?',
    );
    final uri = Uri.parse(url);
    expect(uri.queryParameters['wire'], '2');
    expect(uri.queryParameters['source'], 'practice');
    expect(uri.queryParameters['expected_text'], '¿Cuándo debemos irnos?');
    expect(url, isNot(contains('¿')), reason: 'percent-encoded on the wire');

    final noHint = Uri.parse(
      readAloudRelayUrl('wss://api.example/stream', expectedText: null),
    );
    expect(noHint.queryParameters.containsKey('expected_text'), isFalse);
    expect(noHint.queryParameters['source'], 'practice');
  });
}
