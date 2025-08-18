import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/courses/models/course.dart';
import 'package:fluffychat/pangea/payloadcms_client/payload_client.dart';
import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';

/// Repository for managing courses data from PayloadCMS
class CoursesRepo {
  static PayloadClient? _payloadClient;
  static final GetStorage _courseStorage = GetStorage('courses_storage');

  /// Get or create PayloadClient instance
  static PayloadClient get _client {
    return _payloadClient ??= PayloadClient(baseApiPath: '/cms/api');
  }

  /// Initialize PayloadClient with access token
  static void initializeWithToken(String accessToken) {
    _payloadClient = PayloadClient(
      baseApiPath: '/cms/api',
      accessToken: accessToken,
    );
  }

  /// Cache expiration duration (10 seconds)
  static const Duration _cacheExpiration = Duration(seconds: 10);

  /// Get cached course by ID
  static Course? _getCached(String id) {
    final cachedData = _courseStorage.read('course_$id');
    if (cachedData == null) return null;

    try {
      final cachedAt = DateTime.parse(cachedData['cachedAt'] as String);
      if (DateTime.now().difference(cachedAt) < _cacheExpiration) {
        return Course.fromJson(cachedData['data'] as Map<String, dynamic>);
      }
    } catch (e) {
      _removeCached(id);
      return null;
    }
    return null;
  }

  /// Cache single course
  static Future<void> _setCached(Course course) async {
    final cacheData = {
      'data': course.toJson(),
      'cachedAt': DateTime.now().toIso8601String(),
    };
    _courseStorage.write('course_${course.id}', cacheData);
  }

  /// Remove cached course
  static Future<void> _removeCached(String id) async {
    _courseStorage.remove('course_$id');
  }

  /// Clear all courses cache
  static void clearCache() {
    _courseStorage.erase();
    if (kDebugMode) {
      debugPrint('CoursesRepo: Cache cleared');
    }
  }

  /// Dispose resources
  static void dispose() {
    _payloadClient?.dispose();
    _payloadClient = null;
  }

  /// Find courses with pagination
  static Future<CoursesResponse> find({
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final coursesResponse = await _client.getCollection(
        'courses',
        Course.fromJson,
        page: page,
        limit: limit,
      );

      if (kDebugMode) {
        debugPrint(
          'CoursesRepo: Fetched ${coursesResponse.docs.length} courses',
        );
      }

      return coursesResponse;
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'method': 'find',
          'page': page,
          'limit': limit,
        },
      );

      // Return empty response on error
      return const CoursesResponse(
        docs: [],
        totalDocs: 0,
        limit: 0,
        totalPages: 0,
        page: 1,
        pagingCounter: 1,
        hasPrevPage: false,
        hasNextPage: false,
      );
    }
  }

  /// Find a specific course by ID
  static Future<Course?> findById(String courseId) async {
    final cached = _getCached(courseId);
    if (cached != null) return cached;

    try {
      final course =
          await _client.getDocument('courses', courseId, Course.fromJson);

      await _setCached(course);

      if (kDebugMode) {
        debugPrint('CoursesRepo: Fetched course: ${course.title}');
      }

      return course;
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'method': 'findById',
          'courseId': courseId,
        },
      );
      return null;
    }
  }
}
