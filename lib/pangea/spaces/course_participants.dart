import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';

/// Who the course page lists and in what order, shared by the section preview
/// and the full page so the two can never disagree.
/// Design: course-participants.instructions.md.
class CourseParticipants {
  /// Joined admins, by name.
  final List<User> admins;

  /// Every other joined member but the bot, by name.
  final List<User> members;

  /// Invited and knocking members.
  final List<User> pending;

  const CourseParticipants({
    required this.admins,
    required this.members,
    required this.pending,
  });

  factory CourseParticipants.from(Iterable<User> users) {
    final admins = <User>[];
    final members = <User>[];
    final pending = <User>[];

    for (final user in users) {
      if (user.id == BotName.byEnvironment) continue;
      switch (user.membership) {
        case Membership.join:
          (user.powerLevel >= SpaceConstants.powerLevelOfAdmin
                  ? admins
                  : members)
              .add(user);
        case Membership.invite:
        case Membership.knock:
          pending.add(user);
        default:
          break;
      }
    }

    admins.sort(_byName);
    members.sort(_byName);
    // Invited before knocking, the order the badges read in.
    pending.sort((a, b) {
      if (a.membership != b.membership) {
        return a.membership == Membership.invite ? -1 : 1;
      }
      return _byName(a, b);
    });

    return CourseParticipants(
      admins: admins,
      members: members,
      pending: pending,
    );
  }

  /// Everyone in the course, admins first.
  List<User> get joined => [...admins, ...members];

  /// Name, then id: equal names keep one fixed order across loads.
  static int _byName(User a, User b) {
    final byName = a.calcDisplayname().toLowerCase().compareTo(
      b.calcDisplayname().toLowerCase(),
    );
    return byName != 0 ? byName : a.id.compareTo(b.id);
  }
}
