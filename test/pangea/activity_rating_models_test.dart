import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_rating_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_rating_response.dart';

/// Wire-shape tests for the `/v2/activity/rate` request/response pair
/// (issue #7194): the choreo `ActivityRateRequest` contract omits `comment`
/// and `version_stamp` rather than sending nulls, and the response's
/// `rating_average` may arrive as an int (0 or 1) from JSON.
void main() {
  group('ActivityRatingRequest.toJson', () {
    test('serializes a full request', () {
      final json = const ActivityRatingRequest(
        activityId: 'abc',
        rating: ActivityRatingValue.up,
        comment: 'fun one',
        versionStamp: 'sig123',
      ).toJson();

      expect(json, {
        'activity_id': 'abc',
        'rating': 'up',
        'comment': 'fun one',
        'version_stamp': 'sig123',
        'mock': false,
      });
    });

    test('omits null comment and version stamp', () {
      final json = const ActivityRatingRequest(
        activityId: 'abc',
        rating: ActivityRatingValue.down,
      ).toJson();

      expect(json.containsKey('comment'), isFalse);
      expect(json.containsKey('version_stamp'), isFalse);
      expect(json['rating'], 'down');
    });

    test('omits empty comment', () {
      final json = const ActivityRatingRequest(
        activityId: 'abc',
        rating: ActivityRatingValue.up,
        comment: '',
      ).toJson();

      expect(json.containsKey('comment'), isFalse);
    });
  });

  group('ActivityRatingResponse.fromJson', () {
    test('parses a double average', () {
      final res = ActivityRatingResponse.fromJson(const {
        'activity_id': 'abc',
        'rating_average': 0.75,
        'rating_count': 4,
      });

      expect(res.activityId, 'abc');
      expect(res.ratingAverage, 0.75);
      expect(res.ratingCount, 4);
    });

    test('parses an int average (all-up JSON serializes 1)', () {
      final res = ActivityRatingResponse.fromJson(const {
        'activity_id': 'abc',
        'rating_average': 1,
        'rating_count': 1,
      });

      expect(res.ratingAverage, 1.0);
    });
  });
}
