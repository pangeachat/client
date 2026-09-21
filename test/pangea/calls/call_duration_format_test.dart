import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_panel.dart';
import 'package:fluffychat/routes/chat/calls/call_timeline_event.dart';

/// How long the call was, rendered.
///
/// Two formatters, one assumption. Both build `M:SS` out of `~/` and `%`, and
/// neither can express a negative: Dart's modulo is never negative, so a
/// second short of nothing comes out as "0:59" and a minute short as "59:00".
/// Both are perfectly plausible lengths, printed on the two surfaces whose
/// whole job is to state how long the call was, and nothing downstream could
/// tell one from a real duration.
///
/// It is reachable because the clock underneath is the WALL clock -- these
/// durations are one instant subtracted from another, and a phone correcting
/// its time mid-call moves the ground under that subtraction. The clamp
/// belongs where the assumption is, not at whichever call site remembers it:
/// the live timer had one, the ended-call summary next to it did not, and the
/// summary is the surface a learner actually reads the number off.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final formatters = <(String, String Function(Duration))>[
    ('the call screen', formatCallDuration),
    ('the card in the conversation', CallTimelineEvent.formatDuration),
  ];

  for (final (surface, format) in formatters) {
    group(surface, () {
      test('states an ordinary length', () {
        expect(format(Duration.zero), '0:00');
        expect(format(const Duration(seconds: 68)), '1:08');
        expect(
          format(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03',
        );
      });

      test('never states a length shorter than no time', () {
        expect(format(const Duration(seconds: -1)), '0:00');
        expect(format(const Duration(seconds: -60)), '0:00');
        expect(format(const Duration(hours: -2)), '0:00');
      });
    });
  }
}
