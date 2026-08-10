import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/discovered_sessions_cache.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/features/room_summaries/room_summaries_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_section.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_room_extension.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/stream_extension.dart';

/// The Activities / Course-plan tab of a selected course (world_v2): the
/// course's learning objectives, each with the activities that satisfy it.
/// Objectives are the unlockable unit; activities are interchangeable
/// options. Objectives have no icons yet — a placeholder stands in.
/// Tapping an activity opens it as a first-class world object (`/<uuid>`).
class CourseObjectivesList extends StatefulWidget {
  /// The course room, when shown inside a JOINED course (the card's Course Plan
  /// tab). Null in a PREVIEW of an unjoined plan (SelectedCourse), where
  /// [questId] is supplied directly and there is no completion / in-room
  /// activity context.
  final Room? room;

  /// The v3 quest id whose outline to render. Defaults to the room's
  /// `coursePlan.uuid` when [room] is given; required when [room] is null.
  final String? questId;

  /// Per-activity completion, e.g. `controller.roomSummariesModel
  /// .hasCompletedActivity`. Null in a preview → no completion overlay.
  final bool Function(String activityId)? hasCompletedActivity;

  /// Shrink-wrap the objective list instead of filling/scrolling its own
  /// viewport. Set true when embedded inside another scroll view (the
  /// SelectedCourse / preview pages place this inside an outer `ListView`);
  /// leave false when given a bounded slot (the card's Course Plan tab uses an
  /// `Expanded`).
  final bool shrinkWrap;

  final QuestObjectivesLoader objectivesProvider;

  const CourseObjectivesList({
    required this.objectivesProvider,
    this.room,
    this.questId,
    this.hasCompletedActivity,
    this.shrinkWrap = false,
    super.key,
  });

  @override
  State<CourseObjectivesList> createState() => _CourseObjectivesListState();
}

class _CourseObjectivesListState extends State<CourseObjectivesList> {
  final ScrollController _scrollController = ScrollController();

  /// Course members available to fill activity roles (the start page's invite
  /// math), or null until first loaded. Course-wide (not per-activity), so it's
  /// fetched once then refreshed on room sync; drives dimming of activities that
  /// need more people.
  int? _availableParticipants;
  StreamSubscription? _availableParticipantsSub;

  @override
  void initState() {
    super.initState();
    _loadAvailableParticipants();
    // Open state is read off the map's discovery cache, which discovery updates
    // out-of-band (async, throttled). Rebuild the instant it changes — a session
    // discovered or removed — so a card turns Open / back to plain live, not only
    // on the next room-update sync or a tab re-entry.
    DiscoveredSessionsCache.instance.addListener(_onLiveStateSourcesChanged);
    // Ongoing state ([activeActivityRoomId]) and the dimming count both derive
    // from Matrix room state, so also refresh on room sync (rate-limited). A
    // coursemate opening a session doesn't change our member count, so the
    // rebuild must NOT hinge on it — rebuild every tick (matches the map).
    final client = widget.room?.client;
    if (client != null) {
      _availableParticipantsSub = client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 2))
          .listen((_) {
            if (!mounted) return;
            setState(() {});
            // setStates again only if the count actually changed.
            _loadAvailableParticipants();
          });
    }
  }

  @override
  void dispose() {
    DiscoveredSessionsCache.instance.removeListener(_onLiveStateSourcesChanged);
    _availableParticipantsSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onLiveStateSourcesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAvailableParticipants() async {
    final room = widget.room;
    if (room == null) return; // A preview has no members — nothing to dim.
    final available = await room.availableActivityParticipants();
    // Rebuild only on a real change — the sync handler calls this frequently.
    if (!mounted || available == _availableParticipants) return;
    setState(() => _availableParticipants = available);
  }

  /// Scroll this list from a vertical mouse wheel anywhere over the panel —
  /// including the gaps between cards and the objective headers. Those areas are
  /// hit-transparent, so without an OPAQUE listener the wheel falls straight
  /// through this floating panel to the persistent world map below and zooms it,
  /// while the list (whose own Scrollable only captures a wheel landing on a
  /// card) never moves. Registering on the shared [PointerSignalResolver] yields
  /// to the list's native Scrollable when the wheel IS over a card (it registers
  /// first, being deeper in the tree) and only drives the controller for the
  /// fall-through areas — so there is no double-scroll. See routing.instructions.md.
  void _claimVerticalScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    if (!_scrollController.hasClients) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      resolved as PointerScrollEvent;
      final position = _scrollController.position;
      final target = (position.pixels + resolved.scrollDelta.dy).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      _scrollController.jumpTo(target);
    });
  }

  /// The activity's live map-pin state for the card's colour fill + banner, the
  /// "Open (N)" count, and — for the Waiting state — the roster to draw. Mirrors
  /// the world map's pins, reusing the same resolvers so both surfaces agree:
  ///  * Ongoing wins over Open (the pin ladder). The course-scoped, first-joined
  ///    resume resolver ([Room.activeActivityRoomId]) already collapses multiple
  ///    ongoing rooms to one, so there is at most one Ongoing and it needs no
  ///    count. It splits into Waiting vs Ongoing on the map's exact
  ///    discriminator — [Room.numRemainingRoles] > 0 (seats still empty) →
  ///    [ActivityPinState.ongoingPending] (Waiting), else
  ///    [ActivityPinState.ongoingActive] — and carries the room's roster
  ///    ([Room.largeCardParticipantIds] + remaining seats) so the card can draw
  ///    the same participant row the map's pending pin does.
  ///  * Otherwise, open sessions others started that the learner can join —
  ///    counted from the map's shared [DiscoveredSessionsCache] (best-effort; the
  ///    persistent map behind this panel keeps it fresh), the same source the
  ///    activity start page seeds its join list from.
  /// A preview (no joined [room]) has no live sessions, so cards stay plain.
  ({
    ActivityPinState? state,
    int openSessions,
    List<String> participants,
    int openSlots,
  })
  _liveStateFor(String activityId) {
    final room = widget.room;
    if (room == null) {
      return (
        state: null,
        openSessions: 0,
        participants: const [],
        openSlots: 0,
      );
    }

    final ongoingId = room.activeActivityRoomId(activityId);
    if (ongoingId != null) {
      final live = room.client.getRoomById(ongoingId);
      final remaining = live?.numRemainingRoles ?? 0;
      return (
        state: remaining > 0
            ? ActivityPinState.ongoingPending
            : ActivityPinState.ongoingActive,
        openSessions: 0,
        participants: live?.largeCardParticipantIds ?? const [],
        openSlots: remaining,
      );
    }

    final cached = DiscoveredSessionsCache.instance.forActivity(activityId);
    final open = cached == null
        ? 0
        : ActivitySessionSummariesModel(
            cached,
            activityId: activityId,
          ).openSessions.length;
    return open > 0
        ? (
            state: ActivityPinState.joinable,
            openSessions: open,
            participants: const [],
            openSlots: 0,
          )
        : (state: null, openSessions: 0, participants: const [], openSlots: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: L10n.of(context).coursePlan,
      container: true,
      child: ValueListenableBuilder(
        valueListenable: widget.objectivesProvider.questLoader,
        builder: (context, state, _) {
          switch (state) {
            case AsyncLoading():
            case AsyncIdle():
              return const Center(child: CircularProgressIndicator.adaptive());
            case AsyncError(error: final error):
              return _QuestLoadErrorView(
                error,
                showAddCourse: widget.room?.isRoomAdmin == true,
              );
            case AsyncLoaded():
              // The overall quest-star bar now lives in the course card header
              // (above the tabs — [CourseProgressBar]), so it shows on every tab
              // and in the collapsed mobile peek; the list is just the Missions.
              // Per-Mission stars still show once the shared rollup resolves; a
              // preview has no learner progress.
              final groups = widget.objectivesProvider.filteredObjectiveGroups;
              if (groups.isEmpty) {
                return _QuestLoadErrorView(
                  MissingQuestException(),
                  showAddCourse: widget.room?.isRoomAdmin == true,
                );
              }

              return ValueListenableBuilder(
                valueListenable: widget.objectivesProvider.progression,
                builder: (context, progression, _) {
                  // Scoped to THIS course: the shared resolution spans every
                  // joined course, and Missions are reused across quests (#7771).
                  final hasProgress =
                      widget.room != null &&
                      widget.objectivesProvider.hasResolvedProgress;
                  final list = ListView.separated(
                    controller: widget.shrinkWrap ? null : _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    shrinkWrap: widget.shrinkWrap,
                    physics: widget.shrinkWrap
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    itemCount: groups.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 24.0),
                    itemBuilder: (context, i) {
                      final group = groups[i];
                      return ObjectiveSection(
                        index: i,
                        group: group,
                        hasCompletedActivity: widget.hasCompletedActivity,
                        progress: hasProgress
                            ? widget.objectivesProvider.missionProgress(
                                group.objective.id,
                              )
                            : null,
                        onTap: (ref) {
                          final room = widget.room;
                          if (room == null) {
                            // Token-native open; the course context (if any) is kept,
                            // so the plan closes back to it. See routing.instructions.md.
                            context.go(
                              WorkspaceNav.openActivity(
                                GoRouterState.of(context).uri,
                                ref.activityId,
                              ),
                            );
                            return;
                          }
                          // Immersive in-course open: the token producer drops the
                          // `left=course` card (and any right panel) and keeps the
                          // `?m=course:` scope, so the plan takes the card's slot and
                          // backs out to it. A video hero autostarts (muted).
                          context.go(
                            WorkspaceNav.openCourseActivity(
                              room.id,
                              ref.activityId,
                              autoplay:
                                  ref.plan.heroBlock?.isVideo == true ||
                                  ref.plan.heroBlock?.isYoutube == true,
                            ),
                          );
                        },
                        userStarsByActivity: (activityId) =>
                            widget
                                .room
                                ?.client
                                .userStarsByActivity[activityId] ??
                            0,
                        liveStateByActivity: _liveStateFor,
                        availableParticipants: _availableParticipants,
                      );
                    },
                  );
                  // In a preview the list is embedded in an outer scroll view (shrinkWrap)
                  // with no map behind it, so a wheel can't leak — return it bare. The
                  // standalone course-card panel floats over the map, so capture the wheel
                  // OPAQUELY across the whole panel: the gaps between cards and the
                  // objective headers are hit-transparent, and a wheel there would zoom the
                  // map instead of scrolling the list. See [_claimVerticalScroll].
                  if (widget.shrinkWrap) return list;
                  return Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerSignal: _claimVerticalScroll,
                    child: list,
                  );
                },
              );
          }
        },
      ),
    );
  }
}

class _QuestLoadErrorView extends StatelessWidget {
  final Object error;
  final bool showAddCourse;

  const _QuestLoadErrorView(this.error, {required this.showAddCourse});

  @override
  Widget build(BuildContext context) {
    if (error is MissingQuestException) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            spacing: 12.0,
            children: [
              Semantics(
                container: true,
                child: Text(
                  showAddCourse
                      ? L10n.of(context).missingCourseOutlineCta
                      : L10n.of(context).missingCourseOutline,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              if (showAddCourse)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => context.go(
                      WorkspaceNav.openCoursePage(
                        GoRouterState.of(context).uri,
                        RoomSubpageEnum.addcourse,
                      ),
                    ),
                    icon: Icon(Icons.map_outlined, size: 20.0),
                    label: Text(L10n.of(context).addCoursePlan),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onPrimaryContainer,
                      padding: const EdgeInsets.symmetric(vertical: 14.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: ErrorIndicator(message: error.toLocalizedString(context)),
    );
  }
}
