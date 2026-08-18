import 'package:matrix/matrix.dart';

/// Writes to the signed-in user's Matrix profile — avatar and display name.
///
/// The SDK's own setters (`setAvatar`, `setProfileField`) neither invalidate
/// the SDK's cached profile nor announce the change. Both are left to the
/// member events the homeserver raises in every joined room, which reach the
/// client on a later sync — one per room, so a user in many rooms sees a long,
/// delayed burst, and any surface refetching in the meantime is served the
/// stale cache. Every own-profile writer routes through here so listeners get
/// the same signal the sync raises, right away (#8330).
extension OwnProfileClientExtension on Client {
  static const String _avatarUrlField = 'avatar_url';
  static const String _displayNameField = 'displayname';

  /// Uploads [file] as the own avatar; `null` removes the current one.
  Future<void> setOwnAvatar(MatrixFile? file) =>
      _announceOwnProfileChange(() => setAvatar(file));

  /// Points the own avatar at an already-hosted image (a preset avatar).
  Future<void> setOwnAvatarUrl(Uri url) => _announceOwnProfileChange(
    () => setProfileField(userID!, _avatarUrlField, {
      _avatarUrlField: url.toString(),
    }),
  );

  Future<void> setOwnDisplayName(String displayName) =>
      _announceOwnProfileChange(
        () => setProfileField(userID!, _displayNameField, {
          _displayNameField: displayName,
        }),
      );

  /// Runs [write], then invalidates the cached own profile and announces it on
  /// [onUserProfileUpdate] — the same two steps the sync loop performs for a
  /// member event, so `fetchOwnProfile` listeners refetch from the server.
  Future<void> _announceOwnProfileChange(Future<void> Function() write) async {
    await write();
    final userId = userID!;
    await database.markUserProfileAsOutdated(userId);
    onUserProfileUpdate.add(userId);
  }
}
