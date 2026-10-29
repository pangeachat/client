import 'package:flutter/foundation.dart';

import 'package:sentry_flutter/sentry_flutter.dart' show SentryLevel;

import 'package:fluffychat/features/course_plans/cities/city_index.dart';
import 'package:fluffychat/features/course_plans/payload_client/payload_client.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The listed cities, read once per session from the CMS `cities` collection
/// with the learner's Matrix token (the collection admits Matrix users and
/// service keys, nobody anonymous). The client names a city only when it
/// writes a course's own copy at creation ([CourseMissionsEvent.snapshotOf]);
/// every other city a learner sees arrives in the copy, named by the server.
class CitiesRepo {
  static const String _collection = 'cities';
  static const int _page = 1000;
  static const int _maxPages = 5;

  static Future<CityIndex?>? _read;

  /// Test seam: the index [index] answers with, instead of reading the CMS.
  @visibleForTesting
  static CityIndex? debugIndex;

  /// Test seam: [index] answers null, as it does when the list cannot be read.
  @visibleForTesting
  static bool debugUnavailable = false;

  @visibleForTesting
  static void resetForTest() {
    _read = null;
    debugIndex = null;
    debugUnavailable = false;
  }

  /// The city index, or null when the list could not be read (logged). A
  /// failed read is not kept, so the next caller asks again.
  static Future<CityIndex?> index() {
    if (debugUnavailable) return Future.value(null);
    final seam = debugIndex;
    if (seam != null) return Future.value(seam);
    return _read ??= _load().then((index) {
      if (index == null) _read = null;
      return index;
    });
  }

  static Future<CityIndex?> _load() async {
    try {
      final client = PayloadClient(
        baseUrl: Environment.cmsApi,
        accessToken: MatrixState.pangeaController.userController.accessToken,
      );
      final rows = <Map<String, dynamic>>[];
      for (var page = 1; page <= _maxPages; page++) {
        final response = await client.find<Map<String, dynamic>>(
          _collection,
          (json) => json,
          page: page,
          limit: _page,
          sort: 'key',
          depth: 0,
        );
        rows.addAll(response.docs);
        if (!response.hasNextPage) break;
      }
      final index = CityIndex.fromRows(rows);
      if (index.length == 0) {
        ErrorHandler.logError(
          e: 'The city list is empty; no course copy can name a city',
          data: {},
          level: SentryLevel.warning,
        );
      }
      return index;
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'collection': _collection},
        level: SentryLevel.warning,
      );
      return null;
    }
  }
}
