import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';
import 'package:fluffychat/utils/string_color.dart';
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

/// Builds with [userId]'s **global** Matrix profile — the way any card that
/// knows only a user id draws that user's real name and avatar instead of the
/// localpart and the default letter circle (#8192).
///
/// Why cards fetch instead of being handed a resolved [User]: a session the
/// learner has not joined has no loaded member state — its `room_preview`
/// summary carries bare user ids, and even a local [Room] drops member events
/// under lazy loading — so anything resolved upstream from room state falls
/// back to the localpart. The global profile is the one source always
/// available.
///
/// The SDK owns the caching: [Client.getProfileFromUserId] serves from its
/// database, de-duplicates concurrent requests for the same id, and marks
/// entries outdated off the sync loop. This widget adds no cache of its own,
/// so a resolved profile still costs a future — the fallback shows for a frame
/// whenever this State is built fresh rather than merely rebuilt.
///
/// Prefer [UserProfileAvatar] / [UserProfileName]; reach for this directly only
/// where a card needs the raw [Profile].
///
/// [builder] gets null on the first frame of a cold lookup (and forever if the
/// profile can't be resolved, or when [userId] is null — an unfilled seat), so
/// every caller must render a fallback rather than a spinner: these are avatars
/// inside cards, and a placeholder that resizes on arrival would jump the
/// layout.
class UserProfileBuilder extends StatefulWidget {
  final String? userId;
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
    _profile = null;
    final userId = widget.userId;
    // Null is an unfilled activity seat: nothing to look up, and the caller
    // draws its own empty-seat treatment.
    if (userId == null) return;

    Matrix.of(context).client.getProfileFromUserId(userId).then((profile) {
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

/// The display name for a bare user id, from the same fetched profile the
/// avatar uses. A null [userId] — an unfilled activity seat — draws [fallback].
///
/// [colorize] applies the app's per-name hue to the text (`string_color`), the
/// treatment usernames get elsewhere; the [style]'s own colour wins when it is
/// off.
class UserProfileName extends StatelessWidget {
  final String? userId;
  final String? fallback;
  final TextStyle? style;
  final bool colorize;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const UserProfileName({
    super.key,
    required this.userId,
    this.fallback,
    this.style,
    this.colorize = false,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return UserProfileBuilder(
      userId: userId,
      builder: (context, profile) {
        final userId = this.userId;
        final name = userId == null
            ? null
            : profileDisplayName(userId, profile, L10n.of(context));
        return Text(
          name ?? fallback ?? '',
          style: colorize
              ? (style ?? const TextStyle()).copyWith(
                  color:
                      (theme.brightness == Brightness.light
                          ? name?.darkColor
                          : name?.lightColorText) ??
                      theme.colorScheme.primary,
                )
              : style,
          maxLines: maxLines,
          overflow: overflow,
          textAlign: textAlign,
        );
      },
    );
  }
}
