import 'dart:async';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// Writes to the signed-in user's Matrix profile — avatar and display name.
///
/// The SDK's own setters (`setAvatar`, `setProfileField`) neither invalidate
/// the SDK's cached profile nor announce the change. Both are left to the
/// member events the homeserver raises in every joined room, which reach the
/// client on a later sync — one per room, so a user in many rooms sees a long,
/// delayed burst, and any surface refetching in the meantime is served the
/// stale cache. Every own-profile writer routes through here so listeners get
/// the same signal the sync raises, right away (#8330).
///
/// The homeserver stores the new value first and only then re-sends the
/// member event into every joined room — and on Synapse before 1.150 that
/// propagation runs *inside* the request, so for an account in hundreds of
/// rooms the PUT outlives the reverse proxy's read timeout and the client
/// hears a connection error about a change the server already made. A write
/// here is therefore judged by what the server holds, not by whether the
/// request came back: it resolves as soon as the server is seen holding the
/// value (the PUT completing, or the first member event of the burst prompting
/// a server read), and a request that fails is re-checked against the server
/// before the failure is surfaced.
extension OwnProfileClientExtension on Client {
  static const String _avatarUrlField = 'avatar_url';
  static const String _displayNameField = 'displayname';

  /// Uploads [file] as the own avatar; `null` removes the current one.
  Future<void> setOwnAvatar(MatrixFile? file) async {
    if (file == null) {
      // An empty string removes the avatar; Synapse rejects null (same as the
      // SDK's `setAvatar(null)`). The server then serves no avatar_url at all.
      return _writeOwnProfile(
        () => setProfileField(userID!, _avatarUrlField, {_avatarUrlField: ''}),
        applied: (profile) =>
            profile.avatarUrl == null || profile.avatarUrl.toString().isEmpty,
      );
    }
    // Upload first, outside the write, so the value to verify against is
    // known before the profile PUT goes out.
    final uri = await uploadContent(
      file.bytes,
      filename: file.name,
      contentType: file.mimeType,
    );
    return setOwnAvatarUrl(uri);
  }

  /// Points the own avatar at an already-hosted image (a preset avatar, or an
  /// upload that just finished).
  Future<void> setOwnAvatarUrl(Uri url) => _writeOwnProfile(
    () => setProfileField(userID!, _avatarUrlField, {
      _avatarUrlField: url.toString(),
    }),
    applied: (profile) => profile.avatarUrl?.toString() == url.toString(),
  );

  Future<void> setOwnDisplayName(String displayName) => _writeOwnProfile(
    () => setProfileField(userID!, _displayNameField, {
      _displayNameField: displayName,
    }),
    // Synapse stores the name stripped of surrounding whitespace (and an
    // empty one as no name at all), so compare what it would keep.
    applied: (profile) =>
        (profile.displayname ?? '').trim() == displayName.trim(),
  );

  /// Runs [write] and resolves once the server holds the new value — [applied]
  /// decides that from a fresh server read — then invalidates the cached own
  /// profile and announces it on [onUserProfileUpdate] (the same two steps the
  /// sync loop performs for a member event), so `fetchOwnProfile` listeners
  /// refetch from the server.
  ///
  /// The server is consulted at two moments: when the first own-profile signal
  /// from the sync arrives while the request is still in flight (the server
  /// stores the value before it starts the member-event burst, so the first
  /// event of that burst — which lands long before a large account's PUT
  /// returns — is the one that can confirm it), and when the request fails (a
  /// proxy timeout after the server already stored the value must not be
  /// reported as a failure). A request that fails while the server does not
  /// hold the value rethrows as before.
  Future<void> _writeOwnProfile(
    Future<void> Function() write, {
    required bool Function(ProfileInformation profile) applied,
  }) async {
    final userId = userID!;
    final settled = Completer<void>();

    Future<bool> serverHoldsValue() async {
      try {
        return applied(await _fetchOwnProfileFromServer());
      } catch (_) {
        // The read itself failed; the request's own outcome decides.
        return false;
      }
    }

    // One server read per write, on the first signal only: re-checking on
    // every member event would cost a request per joined room — the storm
    // the cluster's own debounce exists to prevent. If that one read does not
    // confirm the value (a straggler from an earlier burst, or the server
    // normalised the value differently than [applied] expects), the request's
    // own outcome decides.
    late final StreamSubscription<String> firstSignal;
    firstSignal = onUserProfileUpdate.stream.where((id) => id == userId).listen(
      (_) async {
        await firstSignal.cancel();
        if (settled.isCompleted) return;
        if (await serverHoldsValue() && !settled.isCompleted) {
          settled.complete();
        }
      },
    );

    unawaited(
      write().then(
        (_) {
          if (!settled.isCompleted) settled.complete();
        },
        onError: (Object e, StackTrace s) async {
          if (settled.isCompleted) {
            _reportRescuedWrite(e, s, observedBeforeFailure: true);
            return;
          }
          if (await serverHoldsValue()) {
            _reportRescuedWrite(e, s, observedBeforeFailure: false);
            if (!settled.isCompleted) settled.complete();
            return;
          }
          if (!settled.isCompleted) settled.completeError(e, s);
        },
      ),
    );

    try {
      await settled.future;
    } finally {
      await firstSignal.cancel();
    }
    await database.markUserProfileAsOutdated(userId);
    onUserProfileUpdate.add(userId);
  }

  /// The own profile as the server holds it right now — bypassing the SDK's
  /// profile cache, which answers a failed fetch with its stale copy and would
  /// make "applied" unknowable. Mirrors the SDK's raw `getUserProfile`, which
  /// the caching override hides from an extension.
  Future<ProfileInformation> _fetchOwnProfileFromServer() async {
    final json = await request(
      RequestType.GET,
      '/client/v3/profile/${Uri.encodeComponent(userID!)}',
    );
    return ProfileInformation.fromJson(json);
  }

  /// The request failed but the server holds the value. Not a user-facing
  /// failure, but worth counting: it is the signature of the homeserver's
  /// in-request propagation outliving the proxy on a large account.
  void _reportRescuedWrite(
    Object e,
    StackTrace s, {
    required bool observedBeforeFailure,
  }) {
    ErrorHandler.logError(
      e: e,
      s: s,
      m: 'Own-profile write failed after the server applied it',
      data: {'observedBeforeFailure': observedBeforeFailure},
      level: SentryLevel.warning,
    );
  }
}
