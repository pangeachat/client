import 'package:flutter/material.dart';

import 'package:fluffychat/features/user/public_profile_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/network_svg.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/users/level_ribbon.dart';

/// The learner chip — language pair and level — for [userId]'s public profile.
///
/// It draws nothing, and takes no space, for a user with no learning data to
/// show: the bot and the support account have an empty analytics profile, and
/// so does an account that has not picked a language pair yet. Callers stack it
/// with the other public-profile lines ([CountryDisplay], [AboutMeDisplay]),
/// each of which is empty for its own reasons, so a chip that padded itself
/// even while rendering nothing left a band of dead space under the profile
/// (#8238).
class LevelDisplayName extends StatefulWidget {
  final String userId;
  final TextStyle? textStyle;
  final double? iconSize;
  final bool showFlags;

  /// Space around the chip when there is something to draw. The default is the
  /// tight spacing the member list and the invite list want; the profile dialog
  /// passes more, because there it is the first of the public-profile lines and
  /// has to clear the activeness status above it.
  final EdgeInsetsGeometry padding;

  const LevelDisplayName({
    required this.userId,
    this.textStyle,
    this.iconSize,
    this.showFlags = true,
    this.padding = const EdgeInsets.symmetric(vertical: 2.0),
    super.key,
  });

  @override
  State<LevelDisplayName> createState() => _LevelDisplayNameState();
}

class _LevelDisplayNameState extends State<LevelDisplayName> {
  late Future<PublicProfileModel?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  @override
  void didUpdateWidget(covariant LevelDisplayName oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _fetchProfile();
  }

  void _fetchProfile() {
    _profileFuture = MatrixState.pangeaController.userController
        .getPublicProfile(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = widget.textStyle;
    final iconSize = widget.iconSize;
    final showFlags = widget.showFlags;
    final padding = widget.padding;

    return FutureBuilder(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: padding,
            child: const Padding(
              padding: EdgeInsets.all(4.0),
              child: SizedBox(
                width: 12.0,
                height: 12.0,
                child: CircularProgressIndicator.adaptive(),
              ),
            ),
          );
        }

        final analytics = snapshot.data?.analytics;
        final base = analytics?.baseLanguage;
        final target = analytics?.targetLanguage;
        final level = analytics?.level;

        // Nothing learned to show — including the failed-lookup case, which
        // resolves to a null profile.
        if (base == null && target == null && level == null) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: padding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (base != null && target != null) ...[
                if (showFlags) ...[
                  ExcludeSemantics(
                    child: NetworkSvg(
                      svgUrl: base.svgUrl.toString(),
                      placeholder: const Center(
                        child: CircularProgressIndicator(strokeWidth: 0.5),
                      ),
                      width: iconSize ?? 12.0,
                      height: iconSize ?? 12.0,
                    ),
                  ),
                  SizedBox(width: 4.0),
                ],
                Semantics(
                  label:
                      "${L10n.of(context).sourceLanguage}: ${base.displayName}",
                  child: ExcludeSemantics(
                    child: Text(
                      base.langCodeShort.toUpperCase(),
                      style:
                          textStyle ??
                          TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_outlined, size: iconSize ?? 16.0),
              ],
              if (target != null) ...[
                if (showFlags) ...[
                  ExcludeSemantics(
                    child: NetworkSvg(
                      svgUrl: target.svgUrl.toString(),
                      placeholder: const Center(
                        child: CircularProgressIndicator(strokeWidth: 0.5),
                      ),
                      width: iconSize ?? 12.0,
                      height: iconSize ?? 12.0,
                    ),
                  ),
                  SizedBox(width: 4.0),
                ],
                Semantics(
                  label:
                      "${L10n.of(context).targetLanguage}: ${target.displayName}",
                  child: ExcludeSemantics(
                    child: Text(
                      target.langCodeShort.toUpperCase(),
                      style:
                          textStyle ??
                          TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ),
                ),
              ],
              if (level != null) ...[
                const SizedBox(width: 4.0),
                LevelRibbon(level: level, height: (iconSize ?? 16.0) + 2.0),
              ],
            ],
          ),
        );
      },
    );
  }
}
