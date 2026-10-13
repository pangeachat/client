import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart' show Client;

import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// Consumer of the Synapse `member_analytics_profiles` module: every joined
/// member's public analytics profile for one room, in one request, in place
/// of one profile request per member. Contract:
/// member-analytics-profiles.instructions.md (synapse-pangea-chat).
extension MemberAnalyticsProfilesRepo on Client {
  /// The analytics profiles of [roomId]'s joined members, keyed by user id.
  ///
  /// A member missing from the map is one the server could not answer for — a
  /// remote member, or one who joined after the read — and is the caller's to
  /// fetch on its own. An empty map is a successful answer from a server that
  /// predates the module (404): expected during rollout, so not reported.
  Future<Result<Map<String, AnalyticsProfileModel>>> getMemberAnalyticsProfiles(
    String roomId,
  ) async {
    try {
      final request = Request(
        'GET',
        baseUri!.resolveUri(
          Uri(
            path: '/_synapse/client/pangea/v1/member_analytics_profiles',
            queryParameters: {'room_id': roomId},
          ),
        ),
      );
      request.headers['authorization'] = 'Bearer ${bearerToken!}';
      final response = await Response.fromStream(
        await httpClient.send(request),
      );
      if (response.statusCode == 404) return Result.value(const {});
      if (response.statusCode != 200) {
        // This call bypasses `Requests` (Synapse endpoint, Matrix SDK client
        // and token), so it raises the typed failure itself — see
        // repos-and-error-handling.instructions.md.
        throw PangeaHttpException.fromResponse(response);
      }
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      final profiles = (json as Map<String, dynamic>)['profiles'] as Map;
      return Result.value({
        for (final entry in profiles.entries)
          entry.key as String: _parseMemberProfile(
            entry.key as String,
            entry.value,
            roomId,
          ),
      });
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomId': roomId},
        level: PangeaHttpException.severityOf(e),
      );
      return Result.error(e, s);
    }
  }

  /// One member's profile. A member can store any JSON in their own profile
  /// field, so a value the parser rejects costs only that member, as on the
  /// one-request-per-member path: reported, and read as no profile.
  AnalyticsProfileModel _parseMemberProfile(
    String userId,
    Object? value,
    String roomId,
  ) {
    try {
      return AnalyticsProfileModel.fromJson(
        Map<String, dynamic>.from(value as Map),
      );
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomId': roomId, 'userId': userId},
      );
      return AnalyticsProfileModel();
    }
  }
}
