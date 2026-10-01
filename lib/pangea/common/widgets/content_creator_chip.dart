import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/user_profile_builder.dart';
import 'package:fluffychat/routes/home/pangea_logo_svg.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// Who made a piece of content: the owner's avatar and name, as one tappable
/// row.
///
/// The credited person is the content's stored owner MXID — an activity plan's
/// `user_id`, a quest's owner. Name and avatar are resolved from that owner's
/// **Matrix profile** ([UserProfileBuilder], which owns the fetch and its
/// cross-mount seed), never from a second copy of their name stored beside the
/// content: a teacher controls their own credit by editing their profile, and
/// no service resolves anything about the owner on our behalf.
///
/// The three cases, in the order the invariant requires:
///
/// 1. **No owner recorded** ([ownerId] null or blank) — render nothing. An
///    absent owner is not evidence that Pangea made it, and crediting a
///    teacher's hand-built work to Pangea is the failure this widget exists to
///    prevent, so an unknown owner drops the credit rather than guessing one.
/// 2. **[systemOwnerId]** — PangeaChat's name and logo, reserved for content
///    *genuinely* owned by the system user (most of the catalog).
/// 3. **Anyone else** — their profile display name and avatar, falling back to
///    the **full MXID** beside a neutral contact icon when the profile
///    resolves no name: an ugly credit is preferred to a wrong one, and a bare
///    handle reads as a prompt to set a display name.
///
/// Deliberately NOT [profileDisplayName]: that helper falls back to the
/// *localpart*, which would render `@profeceniza02:pangea.chat` as
/// "profeceniza02" — indistinguishable from a display name they chose.
class ContentCreatorChip extends StatelessWidget {
  /// The owner's MXID as stored on the content. Null or blank means no owner
  /// was recorded — case 1 above.
  final String? ownerId;

  /// Diameter of the avatar — the activity info row and the course page sit at
  /// different scales.
  final double avatarSize;

  final TextStyle? textStyle;

  /// Tapping a credit will open that person's profile (client#8825). Wired by
  /// the caller so this stays presentational; the tap target itself exists
  /// either way (see [_CreatorRow]).
  final VoidCallback? onTap;

  const ContentCreatorChip({
    super.key,
    required this.ownerId,
    this.avatarSize = 28.0,
    this.textStyle,
    this.onTap,
  });

  /// The system user: content genuinely owned by Pangea itself.
  ///
  /// Deliberately env-invariant — the choreographer's `SYSTEM_OWNER_MXID` is
  /// this same prod-shaped literal on every environment, so a staging row is
  /// stamped `@system:pangea.chat` too. Never derive it from the homeserver.
  static const String systemOwnerId = '@system:pangea.chat';

  /// Whether [ownerId] credits Pangea itself. False for a blank or absent
  /// owner: unknown is not system-owned.
  static bool isSystemOwned(String? ownerId) =>
      ownerId?.trim() == systemOwnerId;

  /// Whether there is any credit to show at all.
  static bool hasCredit(String? ownerId) => (ownerId?.trim() ?? '').isNotEmpty;

  /// The name to draw for [ownerId] given whatever its profile resolved: the
  /// display name, or the stored MXID whole when there is none.
  static String creatorName({
    required String ownerId,
    required String? displayName,
  }) {
    final name = displayName?.trim() ?? '';
    return name.isEmpty ? ownerId : name;
  }

  @override
  Widget build(BuildContext context) {
    final owner = ownerId?.trim() ?? '';
    if (owner.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final style =
        textStyle ??
        theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);

    if (isSystemOwned(ownerId)) {
      return _CreatorRow(
        avatarSize: avatarSize,
        label: 'PangeaChat',
        style: style,
        onTap: onTap,
        avatar: Container(
          width: avatarSize,
          height: avatarSize,
          padding: EdgeInsets.all(avatarSize * 0.18),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: PangeaLogoSvg(
            width: avatarSize * 0.64,
            forceColor: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      );
    }

    return UserProfileBuilder(
      userId: owner,
      // Null on a cold first frame, and forever if the profile never resolves,
      // so this draws the MXID fallback rather than a spinner — the rule every
      // other profile card follows, and what keeps the row from resizing when
      // a name lands.
      builder: (context, profile) {
        final name = creatorName(
          ownerId: owner,
          displayName: profile?.displayName,
        );
        final hasName = name != owner;
        final avatarUrl = profile?.avatarUrl;
        return _CreatorRow(
          avatarSize: avatarSize,
          label: name,
          style: style,
          onTap: onTap,
          // Avatar seeds a letter circle from `name` whenever it has no
          // image, so a nameless, pictureless owner would be initialled from
          // their handle. That one case draws the neutral contact icon.
          avatar: avatarUrl == null && !hasName
              ? Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.person_outline,
                    size: avatarSize * 0.64,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : Avatar(
                  mxContent: avatarUrl,
                  name: hasName ? name : null,
                  size: avatarSize,
                ),
        );
      },
    );
  }
}

/// The credit's layout, shared by all three cases so they cannot drift apart.
///
/// It is a tap target *today*, before it has anywhere to go (client#8825 lands
/// the profile destination). Shipping the target now is deliberate: it keeps
/// the hit area, the ripple and the button semantics out of that change, so
/// adding the destination cannot re-flow the surfaces that credit someone.
class _CreatorRow extends StatelessWidget {
  final Widget avatar;
  final String label;
  final double avatarSize;
  final TextStyle? style;
  final VoidCallback? onTap;

  const _CreatorRow({
    required this.avatar,
    required this.label,
    required this.avatarSize,
    required this.style,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(avatarSize / 2),
    child: Row(
      children: [
        avatar,
        const SizedBox(width: 8.0),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    ),
  );
}

/// A **labelled** credit — "Created by" over the owner's avatar and name.
///
/// The bare [ContentCreatorChip] is right where the surface already reads as
/// the content's header (the activity start page's info row, where a name
/// under a title is unambiguously the author). It is wrong in a list of
/// controls or beside a call to action, where an unlabelled avatar row reads
/// as a person to contact or a setting to tap. This adds the one word that
/// makes it attribution, and is the form both course surfaces use:
///
/// - **while the course is being made** — the create-course page, at
///   [prominentAvatarSize], where who built the plan is part of deciding to
///   use it; and
/// - **after it exists** — the course page's More section, at
///   [detailAvatarSize], as one of the course's details rather than a banner
///   over a teacher's own description ([client#8819]).
///
/// Both draw from one widget so the two placements cannot drift into two
/// different-looking credits for the same person.
///
/// Collapses to nothing when [ownerId] records no owner, for the reason
/// [ContentCreatorChip] does: an absent owner is never rendered as Pangea.
class ContentCreatorCredit extends StatelessWidget {
  final String? ownerId;

  /// Avatar diameter — [prominentAvatarSize] or [detailAvatarSize].
  final double avatarSize;

  /// See [ContentCreatorChip.onTap]; forwarded unchanged.
  final VoidCallback? onTap;

  /// The create-course page: the credit is part of the decision being made.
  static const double prominentAvatarSize = 36.0;

  /// The More section: the credit is one detail among the course's others.
  static const double detailAvatarSize = 28.0;

  const ContentCreatorCredit({
    super.key,
    required this.ownerId,
    this.avatarSize = detailAvatarSize,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!ContentCreatorChip.hasCredit(ownerId)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L10n.of(context).contentCreatedBy,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4.0),
        ContentCreatorChip(
          ownerId: ownerId,
          avatarSize: avatarSize,
          onTap: onTap,
        ),
      ],
    );
  }
}
