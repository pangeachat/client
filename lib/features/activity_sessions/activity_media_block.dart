/// One stimulus-media item on an activity plan — the client mirror of a CMS
/// `activities-v2` `res.plan.media` block and the choreo `MediaBlock` Pydantic
/// union. Activities carry an ordered, possibly-empty `media` list (a carousel,
/// not a single image); a single image is just a list of length one.
///
/// The discriminator is [blockType] (`image` | `audio` | `video` | `youtube`),
/// the same field name across CMS, choreo, and here. Upload-kind blocks carry a
/// raw [uploadId] referencing the unified CMS `media` collection — NOT a
/// resolved URL — because `upload_id` is a plain text field, so a CMS read at
/// any depth returns the id only. The consumer resolves it to a CDN URL via the
/// `media` collection (see `ActivityMediaRepo`); the resolved URLs land in the
/// `resolved*` fields. `youtube` blocks instead carry a [url] (YouTube ToS
/// forbids storing bytes) and an optional [thumbnailUrl].
///
/// See `.github/.github/instructions/activities.instructions.md` (canonical
/// media model) and `activities.instructions.md`.
class ActivityMediaBlock {
  /// `image` | `audio` | `video` | `youtube`.
  final String blockType;

  /// Unified CMS `media` collection doc id (upload kinds: image/audio/video).
  final String? uploadId;

  /// Source URL (youtube kind only).
  final String? url;

  final String? altText;
  final String? transcript;

  /// Externally-provided thumbnail (youtube kind only).
  final String? thumbnailUrl;

  /// Resolved CDN URLs for upload kinds, filled in by `ActivityMediaRepo`. Null
  /// until resolved; until then [displayUrl] returns null and the renderer
  /// falls back (placeholder / legacy single image).
  final String? resolvedUrl;
  final String? resolvedThumbnailUrl;
  final String? resolvedMediumUrl;

  const ActivityMediaBlock({
    required this.blockType,
    this.uploadId,
    this.url,
    this.altText,
    this.transcript,
    this.thumbnailUrl,
    this.resolvedUrl,
    this.resolvedThumbnailUrl,
    this.resolvedMediumUrl,
  });

  bool get isImage => blockType == 'image';
  bool get isYoutube => blockType == 'youtube';
  bool get isAudio => blockType == 'audio';
  bool get isVideo => blockType == 'video';

  /// The 11-character YouTube video id parsed from [url] (watch / youtu.be /
  /// embed / shorts forms), or null. Used to derive a poster when a `youtube`
  /// block carries no explicit [thumbnailUrl].
  String? get youtubeId {
    final u = url;
    if (u == null) return null;
    return RegExp(
      r'(?:youtu\.be/|youtube\.com/(?:watch\?(?:.*&)?v=|embed/|shorts/|v/))([A-Za-z0-9_-]{11})',
    ).firstMatch(u)?.group(1);
  }

  /// YouTube's own poster image for [youtubeId], or null when the id can't be
  /// parsed — so a thumbnail-less `youtube` block still shows a real poster
  /// instead of falling back to the (non-image) watch URL.
  ///
  /// Uses the `mqdefault` variant (320×180) because it is the smallest poster
  /// that matches a 16:9 video with **no baked-in letterbox bars**. The 4:3
  /// variants (`default`, `hqdefault`, `sddefault`) pad widescreen videos with
  /// black top/bottom bars that survive our square `BoxFit.cover` crop; do not
  /// switch back to them for resolution. `maxresdefault` is 16:9 too but 404s
  /// for videos without an HD source, so it isn't a safe unconditional choice.
  String? get youtubeThumbnailUrl => youtubeId != null
      ? 'https://img.youtube.com/vi/$youtubeId/mqdefault.jpg'
      : null;

  /// The best displayable image URL for a render at [width] px, or null when
  /// the block is non-visual or not yet resolved. Picks the smallest size
  /// variant that covers [width]: thumbnail (256) ≤ medium (512) ≤ original.
  String? displayUrl([double width = 1024]) {
    if (isYoutube) return thumbnailUrl ?? youtubeThumbnailUrl;
    if (resolvedUrl == null) return null;
    if (width <= 256 && resolvedThumbnailUrl != null) {
      return resolvedThumbnailUrl;
    }
    if (width <= 512 && resolvedMediumUrl != null) return resolvedMediumUrl;
    return resolvedMediumUrl ?? resolvedUrl;
  }

  ActivityMediaBlock copyWithResolved({
    required String resolvedUrl,
    String? resolvedThumbnailUrl,
    String? resolvedMediumUrl,
  }) => ActivityMediaBlock(
    blockType: blockType,
    uploadId: uploadId,
    url: url,
    altText: altText,
    transcript: transcript,
    thumbnailUrl: thumbnailUrl,
    resolvedUrl: resolvedUrl,
    resolvedThumbnailUrl: resolvedThumbnailUrl,
    resolvedMediumUrl: resolvedMediumUrl,
  );

  /// From a CMS `res.plan.media` block (snake_case, Payload block shape).
  factory ActivityMediaBlock.fromCmsBlock(Map<String, dynamic> block) =>
      ActivityMediaBlock(
        blockType: (block['blockType'] ?? '') as String,
        uploadId: block['upload_id'] as String?,
        url: block['url'] as String?,
        altText: block['alt_text'] as String?,
        transcript: block['transcript'] as String?,
        thumbnailUrl: block['thumbnail_url'] as String?,
      );

  /// From this model's own [toJson] (cache round-trip).
  factory ActivityMediaBlock.fromJson(Map<String, dynamic> json) =>
      ActivityMediaBlock(
        blockType: (json['block_type'] ?? json['blockType'] ?? '') as String,
        uploadId: json['upload_id'] as String?,
        url: json['url'] as String?,
        altText: json['alt_text'] as String?,
        transcript: json['transcript'] as String?,
        thumbnailUrl: json['thumbnail_url'] as String?,
        resolvedUrl: json['resolved_url'] as String?,
        resolvedThumbnailUrl: json['resolved_thumbnail_url'] as String?,
        resolvedMediumUrl: json['resolved_medium_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'block_type': blockType,
    'upload_id': uploadId,
    'url': url,
    'alt_text': altText,
    'transcript': transcript,
    'thumbnail_url': thumbnailUrl,
    'resolved_url': resolvedUrl,
    'resolved_thumbnail_url': resolvedThumbnailUrl,
    'resolved_medium_url': resolvedMediumUrl,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityMediaBlock &&
          other.blockType == blockType &&
          other.uploadId == uploadId &&
          other.url == url &&
          other.resolvedUrl == resolvedUrl;

  @override
  int get hashCode =>
      blockType.hashCode ^
      uploadId.hashCode ^
      url.hashCode ^
      resolvedUrl.hashCode;
}
