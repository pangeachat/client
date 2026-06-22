import 'package:fluffychat/features/course_plans/payload_client/payload_client.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Resolved CDN URLs for one unified-`media` upload, with its size variants.
typedef ResolvedMedia = ({String url, String? thumbnailUrl, String? mediumUrl});

/// Resolves activity-plan media `upload_id`s to CDN URLs by reading the unified
/// CMS `media` collection directly (Matrix Bearer auth), the same client-side
/// resolution courses use (`CourseMediaRepo`). Choreo deliberately does NOT
/// resolve `upload_id`→URL on the v2 activity path — it returns raw ids — so
/// the consumer owns this hop. See
/// `.github/.github/instructions/activities.instructions.md`.
///
/// `upload_id` is a plain text field on `activities-v2` (not a Payload
/// relationship), so a CMS read at any `depth` returns the id only; this is the
/// required second read. Results are cached in-memory for the session — media
/// URLs are stable, and not persisting them avoids stale-URL bugs across CDN
/// changes.
class ActivityMediaRepo {
  static const String _slug = 'media';

  static final Map<String, ResolvedMedia> _cache = {};

  /// Resolves [uploadIds] to their CDN URLs. Cache-first; one batched `media`
  /// read for the misses. Ids with no media row are simply absent from the
  /// returned map (caller leaves the block unresolved → falls back).
  static Future<Map<String, ResolvedMedia>> resolve(
    List<String> uploadIds,
  ) async {
    final result = <String, ResolvedMedia>{};
    final toFetch = <String>[];
    for (final id in uploadIds) {
      final cached = _cache[id];
      if (cached != null) {
        result[id] = cached;
      } else if (!toFetch.contains(id)) {
        toFetch.add(id);
      }
    }
    if (toFetch.isEmpty) return result;

    final payload = PayloadClient(
      baseUrl: Environment.cmsApi,
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );
    final resp = await payload.find<Map<String, dynamic>>(
      _slug,
      (json) => json,
      where: {
        'id': {'in': toFetch.join(',')},
      },
      limit: toFetch.length,
      depth: 0,
    );

    for (final doc in resp.docs) {
      final id = doc['id'] as String?;
      final url = doc['url'] as String?;
      if (id == null || url == null) continue;
      final sizes = doc['sizes'] as Map<String, dynamic>?;
      String? sizeUrl(String key) => (sizes?[key] as Map?)?['url'] as String?;
      final info = (
        url: url,
        thumbnailUrl: sizeUrl('thumbnail'),
        mediumUrl: sizeUrl('medium'),
      );
      _cache[id] = info;
      result[id] = info;
    }
    return result;
  }
}
