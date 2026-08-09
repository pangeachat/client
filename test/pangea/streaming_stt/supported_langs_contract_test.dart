import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/streaming_stt_gate.dart';

void main() {
  final pack = File(
    'test/pangea/streaming_stt/streaming_supported_langs/'
    'supported_streaming_languages.json',
  );

  test(
    'gate supported set equals the shared contract pack (D5) — pack is the single source',
    () {
      final langs = (jsonDecode(pack.readAsStringSync())['languages'] as List)
          .cast<String>();
      // The literal is FINALIZED to the pack; this proves no W3-routed language was dropped.
      expect(
        StreamingSttGate.supportedLangCodesShort,
        langs.toSet(),
        reason:
            'client widened out of step with choreo — regenerate + copy the pack in the same change',
      );
    },
  );

  test('every language the D3 pack routes is in the gate set', () {
    final langs = (jsonDecode(pack.readAsStringSync())['languages'] as List)
        .cast<String>();
    for (final l in langs) {
      expect(
        StreamingSttGate.supportedLangCodesShort.contains(l),
        isTrue,
        reason: '$l is in the W3-derived pack but missing from the client gate',
      );
    }
  });

  test('english is supported', () {
    expect(StreamingSttGate.supportedLangCodesShort.contains('en'), isTrue);
  });
}
