import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/repo/activity_map_repo.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/network/rate_limit_pause.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

/// #8360. The repo-wide 429 pause shipped in #8160 lived only in
/// `ActivityPlanRepo`, so a 429 on the quest-activity reads was not honoured —
/// the client kept issuing requests the server had already asked it to stop
/// sending (Sentry CLIENT-DXS, CLIENT-E7P, CLIENT-DP3).
///
/// The reasoning carries over unchanged: backoff must be repo-wide, never per
/// key. The world map fires one read per visible pin, so K keys each backing
/// off independently still emit K/cooldown requests and blow the budget on
/// their own.
///
/// These tests never touch the network. That is the point — a suppressed read
/// must return its "we did not ask" answer *before* it reaches `Requests` (or
/// even `MatrixState.pangeaController`), so an unconfigured test binding is
/// itself proof the request was never issued.
void main() {
  var clock = DateTime(2026, 8, 14, 12);

  setUp(() {
    clock = DateTime(2026, 8, 14, 12);
    RateLimitPause.now = () => clock;
    QuestRepo.activityReadPause.reset();
  });

  tearDownAll(() {
    RateLimitPause.now = DateTime.now;
    QuestRepo.activityReadPause.reset();
  });

  PangeaHttpException http(int status) =>
      PangeaHttpException(statusCode: status, method: 'GET', path: '/choreo');

  group('RateLimitPause', () {
    test('starts unpaused', () {
      expect(RateLimitPause().isPaused, isFalse);
    });

    test('a 429 starts the pause', () {
      final pause = RateLimitPause();
      pause.recordFailure(http(429));
      expect(pause.isPaused, isTrue);
    });

    test('only a 429 starts it — other failures are not backpressure', () {
      // A 500 or a 404 says something about the request, not about our rate.
      // Pausing every read on them would turn one bad row into a dead surface.
      for (final status in [404, 500, 503]) {
        final pause = RateLimitPause();
        pause.recordFailure(http(status));
        expect(
          pause.isPaused,
          isFalse,
          reason: '$status is not the server asking us to slow down',
        );
      }
      final pause = RateLimitPause();
      pause.recordFailure(Exception('socket closed'));
      expect(pause.isPaused, isFalse);
    });

    test('the pause lifts on its own — a throttle is not terminal', () {
      final pause = RateLimitPause(const Duration(seconds: 60));
      pause.recordFailure(http(429));
      expect(pause.isPaused, isTrue);

      clock = clock.add(const Duration(seconds: 59));
      expect(pause.isPaused, isTrue);

      clock = clock.add(const Duration(seconds: 2));
      expect(pause.isPaused, isFalse);
    });

    test(
      'reset drops the pause, so a user-initiated refresh is never held',
      () {
        final pause = RateLimitPause();
        pause.recordFailure(http(429));
        pause.reset();
        expect(pause.isPaused, isFalse);
      },
    );

    test('instances are independent — one budget never stalls another', () {
      // Choreo meters `/choreo` and `/subscription` separately, so an activity
      // 429 must never stall checkout.
      final activities = RateLimitPause();
      final other = RateLimitPause();
      activities.recordFailure(http(429));

      expect(activities.isPaused, isTrue);
      expect(other.isPaused, isFalse);
    });
  });

  group('QuestRepo.questActivityCards', () {
    test('is suppressed while the repo is paused', () async {
      QuestRepo.activityReadPause.recordFailure(http(429));

      final result = await QuestRepo.questActivityCards('quest-1');

      expect(result.isError, isTrue);
      expect(
        result.error,
        isA<RateLimitedException>(),
        reason:
            'a suppressed read must be distinguishable from a failed one — '
            'the caller keeps what it has rather than blanking the surface',
      );
    });

    test('the pause is repo-wide, not per quest', () async {
      // The whole defect: K quests each backing off independently still emit
      // K/cooldown requests, which at world-map K exceeds the budget alone.
      QuestRepo.activityReadPause.recordFailure(http(429));

      for (final questId in ['q-a', 'q-b', 'q-c']) {
        final result = await QuestRepo.questActivityCards(questId);
        expect(
          result.error,
          isA<RateLimitedException>(),
          reason: '$questId must not issue a request while paused',
        );
      }
    });

    test(
      'suppression is time-boxed — reads resume once the pause lapses',
      () async {
        QuestRepo.activityReadPause.recordFailure(http(429));
        expect(
          (await QuestRepo.questActivityCards('quest-1')).error,
          isA<RateLimitedException>(),
        );

        clock = clock.add(RateLimitPause.defaultDuration);
        clock = clock.add(const Duration(seconds: 1));

        // Asserted on the pause rather than by calling through again: past this
        // point the read proceeds to the real network path, which a plain test
        // binding cannot serve. What matters is that the gate has reopened — a
        // 429 must throttle the client, never permanently mute a surface.
        expect(QuestRepo.activityReadPause.isPaused, isFalse);
      },
    );
  });

  group('ActivityMapRepo.bboxPins', () {
    final bounds = LatLngBounds(const LatLng(0, 0), const LatLng(1, 1));

    test('shares the quest-activity pause — one budget, one pause', () async {
      // The world map fires both reads: the course-scoped quest listing and
      // this viewport query. They meter against the same `/choreo` activities
      // budget, so honouring a 429 on one while hammering the other honours
      // nothing.
      QuestRepo.activityReadPause.recordFailure(http(429));

      expect(await ActivityMapRepo.bboxPins(bounds: bounds), isNull);
    });

    test('returns null, never an empty list, when suppressed', () async {
      // Null means "we did not ask"; an empty list means "the viewport has no
      // activities". Conflating them blanks the map for the whole pause, which
      // is exactly the silent-empty failure #8360's TO TEST guards against.
      QuestRepo.activityReadPause.recordFailure(http(429));

      final pins = await ActivityMapRepo.bboxPins(bounds: bounds);
      expect(pins, isNull);
      expect(
        pins,
        isNot(const <QuestActivityCard>[]),
        reason: 'an empty list here would blank the map for the whole pause',
      );
    });
  });
}
