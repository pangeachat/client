import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/features/join_codes/share_room_button.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
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
      // No padding of its own: the button is an IconButton like the focus
      // one beside it, and brings the same internal inset and 48px target, so
      // an extra wrapper here would make the two different sizes again.
      if (room.joinCode != null)
        ShareRoomButton(
          room: room,
          tooltip: L10n.of(context).shareCourse,
          icon: const Icon(Icons.share_outlined),
        ),
      // The one camera path that zooms (#7616): course selection only pans, so
      // this button zoom+pan-fits the map to all of the course's activities.
      // Shown while the outline is still loading and hidden only once it has
      // settled with nothing to fit: the bar and the card each warm their own
      // loader, so gating on a loaded outline blinked the button out for a
      // frame or two at every hand-off between them (#8866). A press mid-load
      // is a harmless no-op — the map has nothing to fit yet.
      ValueListenableBuilder(
        valueListenable: objectivesProvider.questLoader,
        builder: (context, outline, _) {
          if (outline is AsyncLoading ||
              objectivesProvider.filteredObjectiveGroups.isNotEmpty) {
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
