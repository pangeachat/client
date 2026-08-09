import 'package:fluffychat/pangea/common/config/environment.dart';

/// Resolve a CMS/CDN media URL to a fetchable [Uri] — the single source of truth
/// for activity/course/topic image-url resolution.
///
/// Since the image-CDN consolidation, the choreo/CMS `url` fields are **absolute
/// CDN urls** (`https://content.pangea.chat/...`) and must be used as-is. Only a
/// legacy *relative* path (cached payloads from before the cutover) gets the CMS
/// origin prepended. Returns null for a null/empty url. See
/// `app_config.dart` (`_allowedImageHosts`) and devops `image-cdn.instructions.md`.
Uri? resolveMediaUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  final isAbsolute = url.startsWith('http://') || url.startsWith('https://');
  return Uri.tryParse(isAbsolute ? url : '${Environment.cmsApi}$url');
}
