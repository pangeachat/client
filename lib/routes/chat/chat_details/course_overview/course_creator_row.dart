import 'package:flutter/material.dart';

import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/content_creator_chip.dart';

/// Who made this course, as one of its **details**.
///
/// It sits in the course page's More section, not at the top of the panel.
/// An activity's credit leads its start page because the page IS that one
/// activity's header; a course page opens on the teacher's own description of
/// their class, and a credit directly under it reads as a banner over their
/// words — the more so on the common catalog path, where the quest behind the
/// course is Pangea's and the room is theirs. Demoting it to a detail keeps
/// the attribution honest without putting it over someone else's text
/// ([client#8819]).
///
/// The credit is the **quest's** owner — who built the course plan — which is
/// what the create-course page credited when this course was made. Who
/// administers the room is a different fact with its own surface (the
/// Participants section).
///
/// It reads the quest the page is already loading rather than fetching
/// anything of its own, so the credit costs no extra round trip. Renders
/// nothing until the quest resolves, and nothing at all for a quest with no
/// owner recorded — an unknown owner is never credited to Pangea
/// ([ContentCreatorChip]).
class CourseCreatorRow extends StatelessWidget {
  final QuestLoader questLoader;

  const CourseCreatorRow({super.key, required this.questLoader});

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AsyncState<QuestOutline>>(
        valueListenable: questLoader,
        builder: (context, state, _) {
          final ownerId = switch (state) {
            AsyncLoaded(value: final outline) => outline.quest.ownerId,
            _ => null,
          };
          if (!ContentCreatorChip.hasCredit(ownerId)) {
            return const SizedBox.shrink();
          }
          return Padding(
            // Aligns with the settings rows below, which carry their own
            // horizontal inset inside the section's padding.
            padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 4.0),
            child: ContentCreatorCredit(ownerId: ownerId),
          );
        },
      );
}
