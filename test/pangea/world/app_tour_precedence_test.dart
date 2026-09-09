import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/world_map.dart';

/// Which sequence the map requests when more than one is due on the same
/// arrival. The rule: the tour outranks the map INTRODUCTION, never the
/// GREETING.
///
/// The regression this locks: an account from before the tutorials shipped
/// arrives with welcome, worldMap AND appTour all pending, plus finished
/// activities on record — and was toured ("great job finishing your first
/// activity!") before ever being greeted.
void main() {
  group('appTourOutranksOrientation', () {
    test('an old account with everything pending is greeted first', () {
      expect(
        appTourOutranksOrientation(
          appTourPending: true,
          welcomePending: true,
          hasFinishedAnActivity: true,
        ),
        isFalse,
      );
    });

    test('a greeted learner due for the tour is toured before the map '
        'introduction — the course-code path, whose worldMap is still '
        'unseen when the tour ends on the World step', () {
      expect(
        appTourOutranksOrientation(
          appTourPending: true,
          welcomePending: false,
          hasFinishedAnActivity: true,
        ),
        isTrue,
      );
    });

    test('no finished activity means no tour, whatever else is pending', () {
      expect(
        appTourOutranksOrientation(
          appTourPending: true,
          welcomePending: false,
          hasFinishedAnActivity: false,
        ),
        isFalse,
      );
    });

    test('a seen tour never runs again', () {
      expect(
        appTourOutranksOrientation(
          appTourPending: false,
          welcomePending: false,
          hasFinishedAnActivity: true,
        ),
        isFalse,
      );
    });
  });
}
