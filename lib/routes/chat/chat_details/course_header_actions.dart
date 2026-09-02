import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/features/join_codes/share_room_button.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/map_context.dart';

/// The course's two header actions — share on the left, focus-on-map on the
/// right, normalized with the activity start page. Shared by the course
/// panel's header ([SpaceDetailsHeader]) and the map's course context bar
/// ([CourseContextBar]), which show the same course and must offer the same
/// actions: the context bar IS the closed panel's header (#8736).
class CourseHeaderActions extends StatelessWidget {
  final Room room;

  /// Gates the focus button: a course whose outline has no renderable Mission
  /// has nothing on the map to fit the camera to.
  final QuestObjectivesLoader objectivesProvider;

  const CourseHeaderActions({
    required this.room,
    required this.objectivesProvider,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (room.joinCode != null)
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ShareRoomButton(
            room: room,
            tooltip: L10n.of(context).shareCourse,
            child: const Icon(Icons.share_outlined),
          ),
        ),
      // The one camera path that zooms (#7616): course selection only pans, so
      // this button zoom+pan-fits the map to all of the course's activities.
      ValueListenableBuilder(
        valueListenable: objectivesProvider.questLoader,
        builder: (context, _, _) {
          if (objectivesProvider.filteredObjectiveGroups.isNotEmpty) {
            return IconButton(
              tooltip: L10n.of(context).focusOnMap,
              icon: const Icon(Icons.my_location),
              onPressed: MapCameraFocusRequests.request,
            );
          }
          return const SizedBox.shrink();
        },
      ),
    ],
  );
}
