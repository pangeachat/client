import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/user/user_profile_cache.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The name to draw for [userId] given its fetched [profile]: the localized
/// name for the bot and support accounts (whose server-side display names are
/// English-only — [localizedPangeaUserName]), then the profile's own display
/// name, and the localpart only when nothing resolved. The profile-side twin of
/// [LocalizedUserDisplayname.localizedDisplayname], which needs a [User].
String profileDisplayName(String userId, Profile? profile, L10n l10n) =>
    localizedPangeaUserName(userId, l10n) ??
    profile?.displayName ??
    userId.localpart ??
    userId;

/// Builds with [userId]'s global Matrix profile, fetching it through
/// [UserProfileCache] — the way any card that knows only a user id draws that
/// user's real name and avatar instead of the localpart and the default letter
/// circle (#8192). See [UserProfileCache] for why room state can't be relied on
/// for a session the learner hasn't joined.
///
/// [builder] gets null on the first frame of a cold lookup (and forever if the
/// profile can't be resolved), so every caller must render a fallback rather
/// than a spinner: these are avatars inside cards, and a placeholder that
/// resizes on arrival would jump the layout.
class UserProfileBuilder extends StatefulWidget {
  final String userId;
  final Widget Function(BuildContext context, Profile? profile) builder;

  const UserProfileBuilder({
    super.key,
    required this.userId,
    required this.builder,
  });

  @override
  State<UserProfileBuilder> createState() => _UserProfileBuilderState();
}

class _UserProfileBuilderState extends State<UserProfileBuilder> {
  Profile? _profile;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Not initState: resolving reads the client off the Provider, which isn't
    // available until dependencies are in place.
    _resolve();
  }

  @override
  void didUpdateWidget(UserProfileBuilder old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _resolve();
  }

  void _resolve() {
    final userId = widget.userId;
    final cached = UserProfileCache.cached(userId);
    if (cached != null) {
      // Synchronous hit — assign directly. In didChangeDependencies there is
      // no build to schedule yet, and setState during didUpdateWidget's
      // rebuild would be redundant.
      _profile = cached;
      return;
    }
    _profile = null;
    UserProfileCache.fetch(Matrix.of(context).client, userId).then((profile) {
      // Drop a stale completion: the widget may have moved to another user
      // (marker recycling) while this lookup was in flight.
      if (mounted && widget.userId == userId) {
        setState(() => _profile = profile);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _profile);
}

/// An [Avatar] for a bare user id: the image and fallback letters come from the
/// user's fetched profile ([UserProfileBuilder]), falling back to the localpart
/// until — or unless — it resolves.
class UserProfileAvatar extends StatelessWidget {
  final String userId;
  final double size;
  final Widget? miniIcon;
  final Offset? presenceOffset;

  const UserProfileAvatar({
    super.key,
    required this.userId,
    this.size = Avatar.defaultSize,
    this.miniIcon,
    this.presenceOffset,
  });

  @override
  Widget build(BuildContext context) => UserProfileBuilder(
    userId: userId,
    builder: (context, profile) => Avatar(
      mxContent: profile?.avatarUrl,
      name: profileDisplayName(userId, profile, L10n.of(context)),
      size: size,
      userId: userId,
      miniIcon: miniIcon,
      presenceOffset: presenceOffset,
    ),
  );
}
