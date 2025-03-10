import 'dart:convert';

import 'package:fluffychat/pangea/activity_planner/activity_plan_request.dart';
import 'package:fluffychat/pangea/activity_planner/activity_plan_response.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';

class ActivitySearchRepo {
  static final GetStorage _activityPlanStorage =
      GetStorage('activity_plan_search_storage');

  static void set(ActivityPlanRequest request, ActivityPlanResponse response) {
    _activityPlanStorage.write(request.storageKey, response.toJson());
  }

  static Future<ActivityPlanResponse> get(ActivityPlanRequest request) async {
    final cachedJson = _activityPlanStorage.read(request.storageKey);
    if (cachedJson != null) {
      final cached = ActivityPlanResponse.fromJson(cachedJson);

      return cached;
    }

    final Requests req = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );

    final Response res = await req.post(
      url: PApiUrls.activityPlanSearch,
      body: request.toJson(),
    );

    final decodedBody = jsonDecode(utf8.decode(res.bodyBytes));
    final response = ActivityPlanResponse.fromJson(decodedBody);

    set(request, response);

    return response;
  }
}
