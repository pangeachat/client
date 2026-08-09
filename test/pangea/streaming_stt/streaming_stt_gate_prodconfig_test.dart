import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/streaming_stt_gate.dart';

// H5 composition (client half): the CLIENT whole-path flag (Environment.liveStreamingSttEnabled)
// is the primary prod-off gate. The prod app config ships liveStreamingSttEnabled=false until the
// owner flip, so `applies` must be false for EVERY language -> the client never opens a streaming
// socket (no factory, batch path). This pins the "off => no streaming" contract at the gate.
void main() {
  test(
    'flag off (prod config) => applies false for every blessed language',
    () {
      for (final lang in StreamingSttGate.supportedLangCodesShort) {
        expect(
          StreamingSttGate.applies(
            flagEnabled: false,
            messageLangCodeShort: lang,
          ),
          isFalse,
          reason: 'client prod-config false must never open streaming (H5)',
        );
      }
    },
  );

  test('flag on (staging config) => applies true for a blessed language', () {
    expect(
      StreamingSttGate.applies(flagEnabled: true, messageLangCodeShort: 'en'),
      isTrue,
    );
  });
}
