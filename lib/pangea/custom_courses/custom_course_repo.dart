import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/custom_courses/custom_course_request_model.dart';
import 'package:fluffychat/pangea/custom_courses/custom_course_response_model.dart';

class CustomCourseRepo {
  static final Map<String, Future<Result<CustomCourseResponseModel>>> _cache =
      {};

  static Future<Result<CustomCourseResponseModel>> get(
    CustomCourseRequestModel request,
    String accessToken,
  ) async {
    final key = request.storageKey;

    final cached = _cache[key];
    if (cached != null) {
      return cached;
    }

    final future = _fetch(request, accessToken);
    _cache[key] = future;
    final result = await future;

    _cache.remove(key);
    return result;
  }

  static Future<Result<CustomCourseResponseModel>> _fetch(
    CustomCourseRequestModel request,
    String accessToken,
  ) async {
    try {
      final Requests req = Requests(accessToken: accessToken);
      final Response res = await req.post(
        url: PApiUrls.requestCustomCourse,
        body: request.toJson(),
      );

      if (res.statusCode != 200) {
        throw res;
      }

      final Map<String, dynamic> json = jsonDecode(
        utf8.decode(res.bodyBytes).toString(),
      );

      final resp = CustomCourseResponseModel.fromJson(json);
      return Result.value(resp);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: request.toJson());
      return Result.error(e);
    }
  }
}
