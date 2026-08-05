import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/streaming_stt_session.dart';

/// Covers the EXACT factory-selection PangeaChatInputRow calls
/// (`buildStreamingSessionFactory`). This proves the real gate wiring: which
/// inputs yield a streaming session vs today's batch `AudioEncoder.wav` path.
///
/// Coverage note: this asserts factory SELECTION (null vs non-null) only. It
/// deliberately never INVOKES the returned factory, because doing so constructs
/// a real `SttAudioCapture` (an `AudioRecorder`, which needs a platform
/// binding). The dual-sink/lifecycle behavior of the built session is covered
/// by streaming_stt_session_test.dart.
void main() {
  const wsUrl = 'wss://api.example/choreo/speech_to_text/stream';

  group('buildStreamingSessionFactory (real PangeaChatInputRow wiring)', () {
    test(
      'flag OFF -> null factory (batch AudioEncoder.wav path), even for en',
      () {
        final factory = buildStreamingSessionFactory(
          flagEnabled: false,
          messageLangCodeShort: 'en',
          accessToken: 'TOKEN',
          wsUrl: wsUrl,
        );
        expect(factory, isNull);
      },
    );

    test(
      'flag ON + every D3 batch-only language -> null factory (batch path)',
      () {
        // 'de' removed: German is an owner-override streaming language now (gets a factory).
        for (final lang in <String>[
          'ar',
          'hi',
          'ja',
          'ko',
          'mn',
          'ru',
          'zh',
          'cmn',
          'yue',
          'zh-Hant',
          'zh-TW',
        ]) {
          final factory = buildStreamingSessionFactory(
            flagEnabled: true,
            messageLangCodeShort: lang,
            accessToken: 'TOKEN',
            wsUrl: wsUrl,
          );
          expect(factory, isNull, reason: '$lang must use batch STT');
        }
      },
    );

    test(
      'flag ON + a widened blessed non-English (es) + token -> a streaming session factory (T8 widen)',
      () {
        // Post-T8 the gate is widened beyond English; a blessed non-English language streams.
        final factory = buildStreamingSessionFactory(
          flagEnabled: true,
          messageLangCodeShort: 'es',
          accessToken: 'TOKEN',
          wsUrl: wsUrl,
        );
        expect(factory, isNotNull);
      },
    );

    test('flag ON + English + token -> a streaming session factory', () {
      final factory = buildStreamingSessionFactory(
        flagEnabled: true,
        messageLangCodeShort: 'en',
        accessToken: 'TOKEN',
        wsUrl: wsUrl,
      );
      expect(factory, isNotNull);
    });

    test(
      'flag ON + English but NO token -> null factory (cannot authorize WS)',
      () {
        final factory = buildStreamingSessionFactory(
          flagEnabled: true,
          messageLangCodeShort: 'en',
          accessToken: null,
          wsUrl: wsUrl,
        );
        expect(factory, isNull);
      },
    );

    // A routed regional alias must reach the relay as the canonical table key.
    // Uses testWidgets so the built session's SttAudioCapture has a platform binding.
    testWidgets('sends a routed regional language as its canonical table key', (
      tester,
    ) async {
      for (final entry in <(String, String)>[
        ('en-US', 'en'),
        ('es-MX', 'es'),
      ]) {
        final (alias, expected) = entry;
        final factory = buildStreamingSessionFactory(
          flagEnabled: true,
          messageLangCodeShort: alias,
          accessToken: 'TOKEN',
          wsUrl: wsUrl,
        );
        expect(
          factory,
          isNotNull,
          reason:
              '$alias is blessed (canonicalizes to a routed key) -> streams',
        );
        final session = factory!();
        expect(
          session.lang,
          expected,
          reason:
              '$alias must reach the relay as $expected (canonical), not the raw alias',
        );
      }
    });
  });
}
