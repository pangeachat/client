import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';
import 'package:fluffychat/pangea/spaces/load_participants_builder.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// The course page's Participants section highlight: a capped row of member
/// avatars with a "+N" overflow chip. The full member cards (levels, roles,
/// member actions) are the section's "All participants" subpage.
class CourseParticipantsPreview extends StatelessWidget {
  final Room room;

  static const int maxAvatars = 8;
  static const double _avatarSize = 38.0;

  const CourseParticipantsPreview({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    return LoadParticipantsBuilder(
      room: room,
      builder: (context, participantsLoader) {
        final participants = participantsLoader.sortedParticipants;
        final overflow = participants.length - maxAvatars;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: [
              ...participants
                  .take(maxAvatars)
                  .map(
                    (user) => Avatar(
                      mxContent: user.avatarUrl,
                      name: user.localizedDisplayname(L10n.of(context)),
                      size: _avatarSize,
                    ),
                  ),
              if (overflow > 0)
                CircleAvatar(
                  radius: _avatarSize / 2,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.secondaryContainer,
                  child: Text(
                    '+$overflow',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
