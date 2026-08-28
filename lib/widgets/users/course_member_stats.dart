import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/user/public_profile_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/users/level_ribbon.dart';

/// What a course shows about one of its members: the stars they have banked in
/// the course's language, and their level in it.
///
/// This is the member's own total across everything they have played in that
/// language — NOT their progress through this course, which the course panel
/// shows as a fraction over a bar. The two are told apart by form: a bare count
/// here, a fraction there. See quests.instructions.md.
///
/// Draws nothing for a member with neither number, the same way
/// [LevelDisplayName] draws nothing for an account with no learning data.
class CourseMemberStats extends StatefulWidget {
  final String userId;

  /// The course's target language, as a language code.
  final String langCode;
  final TextStyle? textStyle;
  final double iconSize;

  const CourseMemberStats({
    required this.userId,
    required this.langCode,
    this.textStyle,
    this.iconSize = 16.0,
    super.key,
  });

  @override
  State<CourseMemberStats> createState() => _CourseMemberStatsState();
}

class _CourseMemberStatsState extends State<CourseMemberStats> {
  late Future<PublicProfileModel?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  @override
  void didUpdateWidget(covariant CourseMemberStats oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _fetchProfile();
  }

  void _fetchProfile() {
    _profileFuture = MatrixState.pangeaController.userController
        .getPublicProfile(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(4.0),
            child: SizedBox(
              width: 12.0,
              height: 12.0,
              child: CircularProgressIndicator.adaptive(),
            ),
          );
        }

        final analytics = snapshot.data?.analytics;
        final stars = analytics?.starsByLanguage(widget.langCode);
        final level = analytics?.levelByLanguage(widget.langCode);

        // A member with nothing to show in this language — including the
        // failed-lookup case, which resolves to a null profile.
        if ((stars == null || stars == 0) && level == null) {
          return const SizedBox.shrink();
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4.0,
          children: [
            if (stars != null && stars > 0) ...[
              Semantics(
                label: "${L10n.of(context).stars}: $stars",
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 2.0,
                    children: [
                      Icon(
                        Icons.star,
                        size: widget.iconSize,
                        color: AppConfig.goldLight,
                      ),
                      Text('$stars', style: widget.textStyle),
                    ],
                  ),
                ),
              ),
            ],
            if (level != null)
              LevelRibbon(level: level, height: widget.iconSize + 2.0),
          ],
        );
      },
    );
  }
}
