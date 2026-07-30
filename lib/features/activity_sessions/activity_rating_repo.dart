import 'dart:convert';

import 'package:http/http.dart';

import 'package:fluffychat/features/activity_sessions/activity_rating_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_rating_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The rater is the activity's owner — the server refuses self-ratings.
class ActivitySelfRatingException implements Exception {}

/// The optional comment was rejected by post-time moderation. The rating
/// itself was NOT recorded; resubmit with a reworded comment or none.
class ActivityCommentRejectedException implements Exception {}

class ActivityRatingRepo {
  /// Submit a thumbs up/down (with optional comment) for an activity.
  ///
  /// One opinion per (user, activity) — the server upserts, so resubmitting
  /// overwrites the previous opinion. Returns the fresh aggregate.
  static Future<ActivityRatingResponse> submitRating(
    ActivityRatingRequest request,
  ) async {
    final Requests req = Requests(
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );

    try {
      final Response res = await req.post(
        url: PApiUrls.activityRate,
        body: request.toJson(),
      );
      final decodedBody = jsonDecode(utf8.decode(res.bodyBytes));
      return ActivityRatingResponse.fromJson(decodedBody);
    } on Response catch (res) {
      if (res.statusCode == 403) throw ActivitySelfRatingException();
      if (res.statusCode == 422) throw ActivityCommentRejectedException();
      rethrow;
    }
  }
}
