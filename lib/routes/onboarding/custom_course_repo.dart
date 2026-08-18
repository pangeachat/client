import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';
import 'package:fluffychat/routes/onboarding/custom_course_request_model.dart';
import 'package:fluffychat/routes/onboarding/custom_course_response_model.dart';

class CustomCourseRepo
    extends BaseRepo<CustomCourseRequestModel, CustomCourseResponseModel> {
  CustomCourseRepo._internal()
    : super(
        cache: MemoryRepoCache(),
        responseFromJson: CustomCourseResponseModel.fromJson,
        cacheDuration: Duration.zero,
      );

  static final CustomCourseRepo _instance = CustomCourseRepo._internal();
  static CustomCourseRepo get instance => _instance;

  @override
  Future<Response> fetch(Requests req, CustomCourseRequestModel request) =>
      req.post(url: PApiUrls.requestCustomCourse, body: request.toJson());

  /// A submitted request is never memoized: each submission is its own backend
  /// side effect, and the `generating` status it returns is stale the moment it
  /// lands. `BaseRepo`'s in-flight dedupe still collapses a double-tap into one
  /// POST, which is the only sharing this repo ever wanted.
  @override
  bool shouldCache(CustomCourseResponseModel response) => false;
}
