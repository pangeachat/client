import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';

/// A ranked member: their place on the course leaderboard and the two numbers
/// it is ranked on. Design: course-leaderboard.instructions.md.
class LeaderboardEntry {
  final User user;

  /// 1-based.
  final int rank;

  /// Stars banked in the course's language; 0 when the profile has none.
  final int stars;

  /// Level in the course's language; null when the member has none there.
  final int? level;

  /// The language code [stars] and [level] are in: the course's, or the
  /// member's own target language when the course records none. Null when
  /// neither is known, in which case there are no numbers to show.
  final String? language;

  const LeaderboardEntry({
    required this.user,
    required this.rank,
    required this.stars,
    this.level,
    this.language,
  });

  LeaderboardMedal? get medal => LeaderboardMedal.forRank(rank);
}

/// The course page's ranking, built once from a room's member list and the
/// members' public analytics profiles, and shared by the section preview and
/// the full page so the two can never disagree.
class CourseLeaderboard {
  /// Joined admins, by name — the line above the ranking.
  final List<User> admins;

  /// Every joined member but the bot, best first.
  final List<LeaderboardEntry> ranked;

  /// Invited and knocking members: shown, never ranked.
  final List<User> pending;

  static const int podiumSize = 3;

  const CourseLeaderboard({
    required this.admins,
    required this.ranked,
    required this.pending,
  });

  List<LeaderboardEntry> get podium => ranked.take(podiumSize).toList();

  List<LeaderboardEntry> get rest => ranked.skip(podiumSize).toList();

  /// [langCode] is the course's language; null ranks each member on their own
  /// target language. [profileOf] returns null for a member whose profile has
  /// not loaded, which ranks as nothing earned.
  factory CourseLeaderboard.rank(
    Iterable<User> members, {
    required String? langCode,
    required AnalyticsProfileModel? Function(String userId) profileOf,
  }) {
    final admins = <User>[];
    final joined = <LeaderboardEntry>[];
    final pending = <User>[];

    for (final user in members) {
      if (user.id == BotName.byEnvironment) continue;
      switch (user.membership) {
        case Membership.join:
          if (user.powerLevel >= SpaceConstants.powerLevelOfAdmin) {
            admins.add(user);
          }
          final profile = profileOf(user.id);
          final language = langCode ?? profile?.targetLanguage;
          joined.add(
            LeaderboardEntry(
              user: user,
              rank: 0,
              stars: language == null
                  ? 0
                  : profile?.starsByLanguage(language) ?? 0,
              level: language == null
                  ? null
                  : profile?.levelByLanguage(language),
              language: language,
            ),
          );
        case Membership.invite:
        case Membership.knock:
          pending.add(user);
        default:
          break;
      }
    }

    // Stars, then level, then name and id: equal members keep one fixed order
    // across loads instead of swapping places (#9212).
    joined.sort((a, b) {
      final byStars = b.stars.compareTo(a.stars);
      if (byStars != 0) return byStars;
      final byLevel = (b.level ?? 0).compareTo(a.level ?? 0);
      if (byLevel != 0) return byLevel;
      return _byName(a.user, b.user);
    });
    admins.sort(_byName);
    // Invited before knocking, the order the badges read in.
    pending.sort((a, b) {
      if (a.membership != b.membership) {
        return a.membership == Membership.invite ? -1 : 1;
      }
      return _byName(a, b);
    });

    return CourseLeaderboard(
      admins: admins,
      ranked: [
        for (final (i, entry) in joined.indexed)
          LeaderboardEntry(
            user: entry.user,
            rank: i + 1,
            stars: entry.stars,
            level: entry.level,
            language: entry.language,
          ),
      ],
      pending: pending,
    );
  }

  static int _byName(User a, User b) {
    final byName = a.calcDisplayname().toLowerCase().compareTo(
      b.calcDisplayname().toLowerCase(),
    );
    return byName != 0 ? byName : a.id.compareTo(b.id);
  }
}

/// The podium's three places and their colours: the theme's bright gold, then
/// silver and bronze.
enum LeaderboardMedal {
  gold,
  silver,
  bronze;

  static LeaderboardMedal? forRank(int rank) => switch (rank) {
    1 => LeaderboardMedal.gold,
    2 => LeaderboardMedal.silver,
    3 => LeaderboardMedal.bronze,
    _ => null,
  };

  Color color(ThemeData theme) => switch (this) {
    LeaderboardMedal.gold => theme.pangea.goldFixedDim,
    LeaderboardMedal.silver => Colors.grey[400]!,
    LeaderboardMedal.bronze => Colors.brown[400]!,
  };

  /// Ink for a number drawn on the medal: the gold's own pair, and for the
  /// two ungoverned metals whichever of black and white the fill's
  /// brightness calls for.
  Color onColor(ThemeData theme) => switch (this) {
    LeaderboardMedal.gold => theme.pangea.onGoldFixed,
    _ =>
      ThemeData.estimateBrightnessForColor(color(theme)) == Brightness.light
          ? Colors.black
          : Colors.white,
  };

  /// The ring around a medalist's avatar, shot through with white.
  LinearGradient ring(ThemeData theme) {
    final color = this.color(theme);
    return LinearGradient(
      colors: [color, Colors.white, color],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  /// A podium row's fill: a wash of the medal over the row's surface, light
  /// enough that `onSurface` text keeps its contrast on every medal.
  Color rowFill(ThemeData theme) => Color.alphaBlend(
    color(theme).withAlpha(_washAlpha),
    theme.colorScheme.surfaceContainerHigh,
  );

  static const int _washAlpha = 0x40;
}
