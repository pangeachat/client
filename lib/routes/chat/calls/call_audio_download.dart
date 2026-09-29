import 'dart:typed_data';

import 'package:matrix/matrix.dart';

/// Reads an `mxc://` URI back into bytes.
///
/// Injected so a caller that only needs to READ a recording -- the P3 merge
/// coordinator, pulling a peer half's bytes to feed the mixer -- is testable
/// without a homeserver, on the same terms `CallAudioUploader`
/// (`call_audio_recorder.dart`) is injected for the write side. The real
/// implementation is [callAudioDownloaderFor], bound to a live [Client].
///
/// PLAIN, never encrypted: like `CallAudioContent.url` and
/// `CallAudioMergedContent.url`, the recording this reads lives on this
/// homeserver's PLAIN media repository -- Pangea's rooms are not end-to-end
/// encrypted -- so there is no attached-file key or IV for a caller of this
/// typedef to supply, and nothing behind it decrypts anything.
typedef CallAudioDownloader = Future<Uint8List> Function(Uri mxc);

/// Splits an `mxc://` URI into the `(serverName, mediaId)` pair
/// `Client.getContent(serverName, mediaId)` expects -- the one piece of logic
/// in this file that is not simply delegating to the SDK, and so the one
/// piece exposed on its own to be proved without a [Client] at all.
///
/// [Uri.host] and [Uri.pathSegments] are used rather than the raw (still
/// percent-escaped) [Uri.path], because `getContent` percent-encodes each
/// argument itself; handing it an already-encoded path would encode it
/// twice.
///
/// The port, if [mxc] names one, is folded into [serverName] as
/// `host:port` -- a literal `:` is a legal, unescaped path-segment character
/// per RFC 3986, and `getContent` percent-encoding it to `%3A` anyway is not
/// a corruption: a server decodes a path segment before matching it, so
/// `%3A` and a literal `:` name the same `server_name`. (Verified: encoding
/// then decoding `'example.com:8448'` round-trips unchanged.) A PORT IS PART
/// OF THE `server_name`, not a detail this reader owns an opinion about --
/// dropping it would silently address the wrong origin server on any
/// deployment that does use one.
///
/// Throws [ArgumentError] for [mxc] that is not a well-formed `mxc://` URI
/// (wrong scheme, no host/authority, or a path that is not EXACTLY one
/// non-empty media-id segment) rather than silently building a request to a
/// nonsense server/media pair -- the SAME fail-fast rule
/// `CallAudioMergedContent.fromJson` and its sibling already apply to a
/// `url` field they cannot use.
///
/// The host check matters on its own, separate from the path check: `mxc:/x`
/// and `mxc:///x` both carry a non-empty PATH (`x`) over an EMPTY host, so
/// checking only the path would let an empty `serverName` reach
/// `Client.getContent` unnoticed.
///
/// The path must be EXACTLY one non-empty segment -- a Matrix media id is
/// always a single opaque token, never a nested path -- rather than joining
/// however many segments [mxc] happens to carry: `mxc://host//` parses to
/// TWO empty segments, which `pathSegments.join('/')` would silently turn
/// into a non-empty-looking `'/'` media id if this only checked for
/// emptiness after joining. Requiring exactly one segment rejects that,
/// `mxc://host/a/b`, and every other shape a single opaque id cannot be, in
/// one rule.
///
/// KNOWN GAP, accepted rather than handled: an IPv6-literal host (`mxc://
/// [::1]:8448/...`) loses its brackets here, since [Uri.host] strips them --
/// `mxcServerAndMediaId` would then build `serverName` as the ambiguous
/// `::1:8448` rather than `[::1]:8448`. Out of scope for what this reader
/// needs: Pangea's own homeserver is addressed by a DNS hostname, never an
/// IP literal, on every deployment this app runs against today.
({String serverName, String mediaId}) mxcServerAndMediaId(Uri mxc) {
  if (mxc.scheme != 'mxc') {
    throw ArgumentError.value(mxc, 'mxc', 'not an mxc:// URI');
  }
  if (mxc.host.isEmpty) {
    throw ArgumentError.value(mxc, 'mxc', 'mxc:// URI has no host');
  }
  final segments = mxc.pathSegments;
  if (segments.length != 1 || segments.single.isEmpty) {
    throw ArgumentError.value(mxc, 'mxc', 'mxc:// URI has no media id');
  }
  return (
    serverName: mxc.hasPort ? '${mxc.host}:${mxc.port}' : mxc.host,
    mediaId: segments.single,
  );
}

/// The [CallAudioDownloader] that talks to a real homeserver.
///
/// Goes through the SDK's own `Client.getContent(serverName, mediaId)` --
/// the Matrix Client-Server media-download call this app already has, rather
/// than a hand-rolled request built from a resolved download URL. It
/// negotiates authenticated-vs-legacy media on its own (matching whatever
/// `CallAudioUploader`'s `client.uploadContent` counterpart already assumes
/// about this homeserver) and returns the response bytes directly; there is
/// no local file cache and no thumbnailing here, on purpose -- a full-call
/// recording is read once, by a background coordinator, not re-rendered on
/// screen the way an image is, so there is nothing here for a cache to save.
CallAudioDownloader callAudioDownloaderFor(Client client) => (mxc) async {
  final split = mxcServerAndMediaId(mxc);
  final response = await client.getContent(split.serverName, split.mediaId);
  return response.data;
};
