import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/discovered_sessions_cache.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/navigation/course_plan_return.dart';
import 'package:fluffychat/features/navigation/panel_entry_intent.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/course_language_scope.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/features/tutorials/tutorial_copy.dart';
import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_controller.dart';
import 'package:fluffychat/features/tutorials/tutorial_seen_backfill.dart';
import 'package:fluffychat/features/tutorials/tutorial_sequences.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_target_ids.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/start_practice.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_badge.dart';
import 'package:fluffychat/routes/courses/course_objectives/activity_carousel.dart';
import 'package:fluffychat/routes/courses/course_objectives/activity_live_state_room_extension.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_objective_circles.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_card.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_section.dart';
import 'package:fluffychat/routes/courses/course_objectives/suggested_activities.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_mismatch_popup.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

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

  /// Shrink-wrap the objective list instead of filling/scrolling its own
  /// viewport. Set true when embedded inside another scroll view (the
  /// SelectedCourse / preview pages place this inside an outer `ListView`);
  /// leave false when given a bounded slot (the card's Course Plan tab uses an
  /// `Expanded`).
  final bool shrinkWrap;

  /// Render the course page's Activities row instead of the plan:
  /// one Mission-less carousel of the plan's activities ranked by the world
  /// map's Priority matrix (#8741). The full, Mission-by-Mission plan is its
  /// "See all" subpage. See quests.instructions.md.
  final bool suggestedOnly;

  /// With [suggestedOnly], the Mission whose row to draw — the one the
  /// learner picked from the circles; null draws the current Mission's.
  final String? missionId;

  /// Mission headers collapse/expand their carousels (the full course plan
  /// subpage, #8357). Off in previews and the Activities row.
  final bool collapsibleMissions;

  /// Display-only: activity cards don't open their plan pages on tap — the
  /// course PREVIEW (#7826), where nothing can be joined or started yet.
  final bool readOnly;

  final QuestObjectivesLoader objectivesProvider;

  const CourseObjectivesList({
    required this.objectivesProvider,
    this.room,
    this.questId,
    this.shrinkWrap = false,
    this.suggestedOnly = false,
    this.missionId,
    this.collapsibleMissions = false,
    this.readOnly = false,
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

  /// Attached to the ObjectiveSection holding the pinged activity, so the
  /// floating ping-bar can tell whether it's on screen and scroll to it.
  final GlobalKey _pingedSectionKey = GlobalKey();

  /// The activity the learner just backed out of to this full plan, taken
  /// once on mount ([CoursePlanReturn]); its Mission is scrolled into view
  /// once, as soon as the plan loads.
  String? _returnActivityId;
  bool _returnScrollScheduled = false;

  /// Attached to the ObjectiveSection holding [_returnActivityId] — unless
  /// that is also the pinged section, which already wears [_pingedSectionKey].
  final GlobalKey _returnSectionKey = GlobalKey();

  /// The pinged activity whose section has been in view — its ping-bar hides
  /// and never comes back this visit. Per-activity, so a NEW ping landing
  /// while the plan is open gets its own bar (#8319).
  String? _seenPingedActivityId;

  bool get _pingedSectionSeen => _seenPingedActivityId == _pingedActivityId;

  /// Missions the learner folded, by id. Held here rather than in each
  /// [ObjectiveSection] because the list builds lazily and disposes sections
  /// scrolled out of view (#9248).
  final Set<String> _collapsedMissionIds = {};

  void _toggleMissionCollapsed(String missionId) => setState(() {
    if (!_collapsedMissionIds.remove(missionId)) {
      _collapsedMissionIds.add(missionId);
    }
  });

  /// This list is the course card's full course plan — the one surface an
  /// activity's back arrow returns to (routing.instructions.md).
  bool get _isFullCoursePlan =>
      widget.room != null && !widget.suggestedOnly && !widget.readOnly;

  @override
  void initState() {
    super.initState();
    final room = widget.room;
    if (_isFullCoursePlan && room != null) {
      _returnActivityId = CoursePlanReturn.take(room.id);
    }
    _loadAvailableParticipants();
    // The course page stashes the ping asynchronously (it reads the timeline),
    // usually after this list first builds — rebuild when it lands.
    CoursePingBadgeCache.instance.addListener(_onLiveStateSourcesChanged);
    _scrollController.addListener(_checkPingedSectionSeen);
    _registerTutorialLaunchers();
    _maybeStartOrientation();
    // Once more when the profile lands, in case it loads after every other hook
    // has had its turn — and when the veteran backfill resolves, which may have
    // just marked the welcome seen.
    MatrixState.pangeaController.userController.initCompleter.future.then(
      (_) => _maybeStartOrientation(),
    );
    TutorialSeenBackfill.instance.ensureResolved().then(
      (_) => _maybeStartOrientation(),
    );
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
    CoursePingBadgeCache.instance.removeListener(_onLiveStateSourcesChanged);
    _availableParticipantsSub?.cancel();
    _scrollController.dispose();
    if (_hostsTutorial) {
      _tutorials
        ..unregisterLauncher(TutorialEnum.welcome, _launchWelcomeTutorial)
        ..unregisterLauncher(TutorialEnum.coursePlan, _launchCoursePlanTutorial)
        // Nothing can show the remaining steps once this list is gone. Progress
        // is persisted, so the next visit resumes where this one left off.
        ..releaseSequence(TutorialSequences.courseOrientationSequence);
    }
    super.dispose();
  }

  // Orientation tutorials — the greeting, then the course plan.
  // Design: tutorials.instructions.md

  TutorialOverlayController get _tutorials =>
      MatrixState.tutorialOverlayController;

  /// At most one pending check, so the rebuild-heavy live-state listeners cost
  /// one callback rather than one per notification.
  bool _orientationCheckScheduled = false;

  /// Whether THIS list instance is the one that runs the course tutorial.
  ///
  /// The course page's Activities row and its pushed full-plan subpage can both
  /// be mounted — so exactly one is allowed to claim the carousel target and
  /// drive the sequence. The Activities row wins: it is what a learner sees when
  /// they open the course. A preview of an unjoined plan teaches nothing and is
  /// excluded by having no room.
  bool get _hostsTutorial => widget.suggestedOnly && widget.room != null;

  void _registerTutorialLaunchers() {
    if (!_hostsTutorial) return;
    _tutorials
      ..registerLauncher(TutorialEnum.welcome, _launchWelcomeTutorial)
      ..registerLauncher(TutorialEnum.coursePlan, _launchCoursePlanTutorial);
  }

  /// Re-asked on every rebuild source rather than checked once: the quest
  /// outline, the ranked shortlist, and the profile all land asynchronously, and
  /// a single early check would simply find nothing and give up.
  void _maybeStartOrientation() {
    if (!_hostsTutorial) return;
    if (_orientationCheckScheduled) return;
    _orientationCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _orientationCheckScheduled = false;
      _checkOrientation();
    });
    // A post-frame callback only runs if a frame is coming; a re-ask arriving
    // between frames (initCompleter, live-state listeners) would otherwise
    // leave the flag latched true and swallow every later re-ask.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _checkOrientation() {
    if (!mounted) return;

    if (!MatrixState
        .pangeaController
        .userController
        .initCompleter
        .isCompleted) {
      return;
    }

    // The veteran backfill may be about to mark the welcome seen — wait for
    // its one evaluation; resolution re-asks (initState).
    if (!TutorialSeenBackfill.instance.isResolved) return;

    if (!_tutorials.isPending(TutorialEnum.welcome) &&
        !_tutorials.isPending(TutorialEnum.coursePlan)) {
      return;
    }

    // Before resuming, not after: a resume onto a surface that isn't there
    // relaunches a step that immediately dismisses itself again.
    if (MatrixState.pAnyState.getRenderBox(TutorialTargetIds.coursePanel) ==
        null) {
      return;
    }

    if (_tutorials.hasActiveSequence) {
      _tutorials.resumeIfStranded();
      return;
    }

    _tutorials.requestSequence(TutorialSequences.courseOrientationSequence);
  }

  Future<void> _launchWelcomeTutorial() async {
    if (!mounted) return;
    final greeting = await TutorialCopy.targetLanguageGreeting(context);
    if (!mounted) return;
    _tutorials.launchTutorial(
      context: context,
      tutorial: TutorialModel.welcome(greeting),
      isFocused: true,
    );
  }

  Future<void> _launchCoursePlanTutorial() async {
    if (!mounted) return;
    final room = widget.room;
    final courseName =
        room?.getLocalizedDisplayname(MatrixLocals(L10n.of(context))) ?? '';

    _tutorials.launchTutorial(
      context: context,
      tutorial: TutorialModel(
        tutorialType: TutorialEnum.coursePlan,
        stepsData: [
          // Lights the whole course panel — header, progress and plan — so the
          // step is plainly about THIS course. A full-height target leaves no
          // room beside it, so the card is seated at the bottom of the panel.
          TutorialStepData.single(
            targetKey: TutorialTargetIds.coursePanel,
            canShowNextStep: () => true,
            tooltipArgs: () => [courseName],
          ),
        ],
      ),
      isFocused: true,
    );
  }

  void _onLiveStateSourcesChanged() {
    if (mounted) setState(() {});
    _maybeStartOrientation();
  }

  /// The activity a course ping pointed at, when it's for THIS course.
  /// Previews (no room) never match. See [CoursePingBadgeCache].
  String? get _pingedActivityId {
    final ping = CoursePingBadgeCache.instance.value;
    if (ping == null || ping.courseId != widget.room?.id) return null;
    return ping.activityId;
  }

  /// Hide the ping-bar for good once the pinged section shows in the
  /// viewport. Checked on scroll and post-frame; the section not being built
  /// at all (lazy list, far below the fold) counts as not seen.
  void _checkPingedSectionSeen() {
    if (_pingedSectionSeen || _pingedActivityId == null) return;
    final sectionBox = _pingedSectionKey.currentContext?.findRenderObject();
    final listBox = context.findRenderObject();
    if (sectionBox is! RenderBox ||
        listBox is! RenderBox ||
        !sectionBox.attached ||
        !listBox.attached) {
      return;
    }
    final top = sectionBox.localToGlobal(Offset.zero, ancestor: listBox).dy;
    // Seen once a meaningful slice of the section (or all of it, when the
    // learner scrolled past) is inside the viewport.
    if (top < listBox.size.height - 100.0) {
      setState(() => _seenPingedActivityId = _pingedActivityId);
    }
  }

  /// Scroll to the section [sectionKey] is attached to. The list builds
  /// lazily, so an unbuilt target has no context to ensureVisible — step down
  /// a viewport at a time until it mounts, then settle on it. [animate] false
  /// jumps instead: arriving back on the plan puts the learner where they
  /// left off, rather than playing a scroll they did not ask for.
  Future<void> _scrollToSection(
    GlobalKey sectionKey, {
    bool animate = true,
  }) async {
    while (mounted &&
        sectionKey.currentContext == null &&
        _scrollController.hasClients) {
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent) break;
      final target = (position.pixels + position.viewportDimension * 0.8).clamp(
        0.0,
        position.maxScrollExtent,
      );
      if (animate) {
        await _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 150),
          curve: Curves.linear,
        );
      } else {
        _scrollController.jumpTo(target);
        await WidgetsBinding.instance.endOfFrame;
      }
    }
    final sectionContext = sectionKey.currentContext;
    if (!mounted || sectionContext == null) return;
    await Scrollable.ensureVisible(
      sectionContext,
      duration: animate ? const Duration(milliseconds: 300) : Duration.zero,
      curve: Curves.easeOut,
      alignment: 0.1,
    );
  }

  Future<void> _scrollToPinged() => _scrollToSection(_pingedSectionKey);

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

  /// The activity's live map-pin state for the card's frame and pill, its open
  /// sessions, and — for the Waiting state — the roster to draw. Mirrors
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
  ///    counted from the map's shared [DiscoveredSessionsCache], scoped to the
  ///    sessions this course lists (#9026) (best-effort; the persistent map
  ///    behind this panel keeps it fresh), the same source the activity start
  ///    page seeds its join list from.
  /// A preview (no joined [room]) has no live sessions, so cards stay plain.
  ActivityLiveState _liveStateFor(String activityId) =>
      widget.room?.activityLiveState(activityId) ?? noActivityLiveState;

  /// The [PinSignals] the Priority matrix scores this activity on, built from
  /// the same live state the cards render. `recency` stays 0: open sessions
  /// reach this surface through the discovery cache, which carries no
  /// per-session start time. See [rankSuggestedActivities].
  PinSignals _signalsFor(
    String activityId,
    Map<String, MissionXpBreakdown> xpByActivity,
  ) => PinSignals(
    state: _liveStateFor(activityId).state ?? ActivityPinState.available,
    completionFraction: _finished(xpByActivity, activityId) ? 1.0 : 0.0,
    pinged: activityId == _pingedActivityId,
  );

  /// The learner's XP per activity from its saved sessions in their current
  /// language (#9559) — a preview's too, so a course they haven't joined
  /// still shows what they earned in its activities elsewhere. Read once per
  /// build: it walks the rooms.
  Map<String, MissionXpBreakdown> _xpByActivity() =>
      widget.objectivesProvider.client.cachedXpBreakdownByActivity;

  /// Whether the learner has finished [activityId]: any XP from a saved
  /// session of it in their current language (#9559) — the one rule every
  /// completed stamp reads.
  static bool _finished(
    Map<String, MissionXpBreakdown> xpByActivity,
    String activityId,
  ) => (xpByActivity[activityId]?.total ?? 0) > 0;

  /// Where a Mission card anchors its language-switch popup.
  static String _languageTargetId(String missionId) =>
      'mission_language_$missionId';

  /// A tap that offers the switch to [language] in [missionId]'s card's
  /// mismatch popup, then runs [then] once it has switched — on this page's
  /// own context, so a rebuild under the switch (the outline re-reading in
  /// the new display language) can't leave it acting on a gone widget.
  VoidCallback _switchLanguageThen(
    String missionId,
    LanguageModel language,
    VoidCallback then,
  ) =>
      () => LanguageMismatchPopup.show(
        context: context,
        targetId: _languageTargetId(missionId),
        message: L10n.of(context).missionLanguageMismatchDesc(
          CourseLanguageScope.courseLanguageName(widget.room, L10n.of(context)),
        ),
        targetLanguage: language,
        onConfirm: () => WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) then();
        }),
      );

  void _openMissionDetails(String missionId) => context.go(
    WorkspaceNav.openObjectiveDetail(
      GoRouterState.of(context).uri,
      missionId,
      courseId: widget.room?.id,
    ),
  );

  void _practiceMission(String missionId) =>
      startPractice(context, ConstructTypeEnum.vocab, missionId: missionId);

  void _openSession(String roomId) {
    PanelEntryIntent.instance.armForSwap();
    context.go(
      WorkspaceNav.openRoomById(GoRouterState.of(context).uri, roomId),
    );
  }

  void _openActivity(QuestActivity ref) {
    if (widget.readOnly) return;
    final room = widget.room;
    // The activity takes the card's slot, and the pressed card goes with it,
    // so the activity panel that mounts claims focus
    // (routing.instructions.md, "Every panel is a named group to assistive
    // tech").
    PanelEntryIntent.instance.armForSwap();
    if (room == null) {
      // Token-native open; the course context (if any) is kept, so the plan
      // closes back to it. See routing.instructions.md.
      context.go(
        WorkspaceNav.openActivity(
          GoRouterState.of(context).uri,
          ref.activityId,
        ),
      );
      return;
    }
    // Immersive in-course open: the token producer drops the `left=course`
    // card (and any right panel) and keeps the `?m=course:` scope, so the plan
    // takes the card's slot and backs out to it. A video hero sets the
    // token's autoplay field, which nothing reads today, so nothing plays
    // until tapped.
    context.go(
      WorkspaceNav.openCourseActivity(
        room.id,
        ref.activityId,
        autoplay:
            ref.plan.heroBlock?.isVideo == true ||
            ref.plan.heroBlock?.isYoutube == true,
        fromCoursePlan: _isFullCoursePlan,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Re-asked from build, which is the ONLY hook that always runs when the
    // carousel this tutorial points at appears. The quest outline loads
    // asynchronously, so the first frame is a spinner and the carousel does not
    // exist yet; the listeners wired in initState (ping cache, discovery cache,
    // room sync) need not fire when it lands, so the check could sit unasked
    // until something unrelated happened to poke it — which is why the tutorial
    // only showed up on a SECOND visit to the course. Debounced to one
    // post-frame callback by [_maybeStartOrientation].
    _maybeStartOrientation();

    return Semantics(
      label: widget.suggestedOnly
          ? L10n.of(context).learningObjective
          : L10n.of(context).coursePlan,
      container: true,
      child: ValueListenableBuilder(
        valueListenable: widget.objectivesProvider.questLoader,
        builder: (context, state, _) {
          switch (state) {
            case AsyncLoading():
            case AsyncIdle():
              return const Center(child: CircularProgressIndicator.adaptive());
            case AsyncError(error: final error):
              return QuestLoadErrorView(
                error,
                showAddCourse: widget.room?.isRoomAdmin == true,
              );
            case AsyncLoaded():
              // Per-Mission stars still show once the shared rollup resolves; a
              // preview has no learner progress. (The overall quest-star bar
              // rides above this list on the course page.)
              final groups = widget.objectivesProvider.filteredObjectiveGroups;
              final anchorId = widget.objectivesProvider.anchorMissionId;
              if (groups.isEmpty) {
                return QuestLoadErrorView(
                  MissingQuestException(),
                  showAddCourse: widget.room?.isRoomAdmin == true,
                );
              }

              // Also on the XP cache, whose loading flag the Mission header
              // shimmers on (#9559).
              return ListenableBuilder(
                listenable: Listenable.merge([
                  widget.objectivesProvider.progression,
                  MissionXpCache.instance,
                ]),
                builder: (context, _) {
                  final xpByActivity = _xpByActivity();
                  if (widget.suggestedOnly) {
                    // The course page's Mission card and its activities
                    // (#9437), ordered by the same Priority matrix the map
                    // ranks pins by, the learner's own unfinished sessions
                    // first. The row is the Mission's whole queue (#9559):
                    // finished activities stay, ranked after what is still
                    // to do. Empty only while the course is complete or has
                    // no Mission; the page renders its own card for that.
                    final current =
                        widget.objectivesProvider.objectiveGroup(
                          widget.missionId,
                        ) ??
                        widget.objectivesProvider.currentObjectiveGroup;
                    if (current == null) return const SizedBox.shrink();
                    final missionId = current.objective.id;
                    final suggested = rankSuggestedActivities(
                      groups: [current],
                      missionGradient:
                          widget.objectivesProvider.missionGradient,
                      signalsFor: (id) => _signalsFor(id, xpByActivity),
                      cap: null,
                      includeOngoing: true,
                      includeCompleted: true,
                      // The carousel's own dimming rule, so a card ranks
                      // where it looks.
                      canStart: (activity) => ActivityCarousel.canStart(
                        availableParticipants: _availableParticipants,
                        complete: _finished(xpByActivity, activity.activityId),
                        live: _liveStateFor(activity.activityId).state != null,
                        roles: activity.plan.req.numberOfParticipants,
                      ),
                    );
                    final activities = [
                      for (final suggestion in suggested) suggestion.activity,
                    ];
                    // Play opens the row's first card, and that card carries a
                    // small "Up next" in Play's colour (#9559), so the two are
                    // one thing. The row leads with a session the learner is
                    // already in — Play reads "Continue activity" and reopens
                    // it, so a started activity gets finished before a new one
                    // starts — then a coursemate's open session, then the best
                    // unfinished activity ("Next activity"), then a finished
                    // one for another round ("Play again"), then what the
                    // course can't fill yet. Each Mission keeps to its own
                    // activities: a session from another Mission resumes from
                    // that Mission's card or Chats.
                    final inRow = activities.firstOrNull;
                    final playTarget = inRow ?? current.activities.firstOrNull;
                    final ongoingRoomId = inRow == null
                        ? null
                        : widget.room?.activeActivityRoomId(inRow.activityId);
                    final replay =
                        playTarget != null &&
                        ongoingRoomId == null &&
                        _finished(xpByActivity, playTarget.activityId) &&
                        _liveStateFor(playTarget.activityId).state == null;
                    final l10n = L10n.of(context);
                    final hasProgress = widget.room != null;
                    final position = widget
                        .objectivesProvider
                        .filteredObjectiveGroups
                        .indexOf(current);
                    // A joined course in another language than the
                    // learner's (#9559): its progress counts only there, so
                    // the card hides it, and the Mission's detail page and
                    // its Practice go through the same "switch language?"
                    // popup a send in such a session does. Its base
                    // language can't be switched to, so there the link is
                    // plain and Practice is hidden.
                    final room = widget.room;
                    final otherLanguage =
                        room != null &&
                        !CourseLanguageScope.courseInTargetLanguage(room);
                    final switchTo = otherLanguage
                        ? CourseLanguageScope.courseSwitchLanguage(room)
                        : null;
                    final languageName = otherLanguage
                        ? CourseLanguageScope.courseLanguageName(room, l10n)
                        : null;
                    return MissionCard(
                      group: current,
                      index: position < 0 ? null : position + 1,
                      progress: hasProgress
                          ? widget.objectivesProvider.missionProgress(missionId)
                          : null,
                      breakdown: hasProgress
                          ? widget.objectivesProvider.missionXpBreakdown(
                              missionId,
                              byActivity: xpByActivity,
                            )
                          : null,
                      onPlay: widget.readOnly || playTarget == null
                          ? null
                          : ongoingRoomId != null
                          ? () => _openSession(ongoingRoomId)
                          : () => _openActivity(playTarget),
                      playLabel: ongoingRoomId != null
                          ? l10n.missionContinueActivity
                          : replay
                          ? l10n.playAgain
                          : l10n.missionNextActivity,
                      playTarget: playTarget?.plan.title,
                      onDetails: !hasProgress || widget.readOnly
                          ? null
                          : switchTo != null
                          ? _switchLanguageThen(
                              missionId,
                              switchTo,
                              () => _openMissionDetails(missionId),
                            )
                          : otherLanguage
                          ? null
                          : () => _openMissionDetails(missionId),
                      // In another language, Practice first offers the
                      // switch; in the learner's base language, which can't
                      // be switched to, there is nothing to practise, so it
                      // is hidden — as on the Mission's detail page.
                      onPractice: switchTo != null
                          ? _switchLanguageThen(
                              missionId,
                              switchTo,
                              () => _practiceMission(missionId),
                            )
                          : otherLanguage
                          ? null
                          : () => _practiceMission(missionId),
                      otherLanguageName: languageName,
                      onSwitchLanguage: switchTo == null || widget.readOnly
                          ? null
                          : _switchLanguageThen(missionId, switchTo, () {}),
                      // The popup's anchor, registered only when there is a
                      // switch to offer.
                      languageTargetId: switchTo == null
                          ? null
                          : _languageTargetId(missionId),
                      // A joined course in the learner's language whose
                      // progress hasn't resolved yet.
                      loading: widget.objectivesProvider.progressLoading,
                      // The Mission's activities live in its card: they
                      // are what fills it (#9420).
                      activities: activities.isEmpty
                          ? null
                          : ActivityCarousel(
                              activities: activities,
                              onTap: (activity) {
                                // A session the learner is in reopens its
                                // chat; anything else opens its start page.
                                final ongoingId = widget.room
                                    ?.activeActivityRoomId(activity.activityId);
                                if (ongoingId != null) {
                                  _openSession(ongoingId);
                                } else {
                                  _openActivity(activity);
                                }
                              },
                              xpByActivity: (id) =>
                                  xpByActivity[id]?.total ?? 0,
                              liveStateByActivity: _liveStateFor,
                              availableParticipants: _availableParticipants,
                              pingedActivityId: _pingedActivityId,
                              highlightedActivityId: widget.readOnly
                                  ? null
                                  : inRow?.activityId,
                              interactive: !widget.readOnly,
                            ),
                    );
                  }
                  // Scoped to THIS course: the shared resolution spans every
                  // joined course, and Missions are reused across quests (#7771).
                  final hasProgress =
                      widget.room != null &&
                      widget.objectivesProvider.hasResolvedProgress;
                  // The pinged activity's section, for the card badge and the
                  // floating ping-bar. A ping for an activity no longer in the
                  // plan resolves to no badge at all.
                  final pingedActivityId = _pingedActivityId;
                  final pingedGroupIndex = pingedActivityId == null
                      ? -1
                      : groups.indexWhere(
                          (g) => g.activities.any(
                            (a) => a.activityId == pingedActivityId,
                          ),
                        );
                  if (pingedGroupIndex >= 0 && !_pingedSectionSeen) {
                    // Catch the initially-visible case (and any relayout)
                    // that the scroll listener alone would miss.
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _checkPingedSectionSeen(),
                    );
                  }
                  final returnActivityId = _returnActivityId;
                  final returnGroupIndex = returnActivityId == null
                      ? -1
                      : groups.indexWhere(
                          (g) => g.activities.any(
                            (a) => a.activityId == returnActivityId,
                          ),
                        );
                  final returnSectionKey = returnGroupIndex == pingedGroupIndex
                      ? _pingedSectionKey
                      : _returnSectionKey;
                  if (returnGroupIndex >= 0 && !_returnScrollScheduled) {
                    _returnScrollScheduled = true;
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _scrollToSection(returnSectionKey, animate: false),
                    );
                  }
                  final classIndex = CourseObjectiveCircles.classLocationIndex(
                    groups,
                    DateTime.now(),
                  );
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
                        key: i == pingedGroupIndex
                            ? _pingedSectionKey
                            : i == returnGroupIndex
                            ? _returnSectionKey
                            : null,
                        pingedActivityId: i == pingedGroupIndex
                            ? pingedActivityId
                            : null,
                        collapsed: _collapsedMissionIds.contains(
                          group.objective.id,
                        ),
                        onToggleCollapsed: widget.collapsibleMissions
                            ? () => _toggleMissionCollapsed(group.objective.id)
                            : null,
                        isUpNext: group.objective.id == anchorId,
                        isClassLocation: i == classIndex,
                        index: i + 1,
                        missionCount: groups.length,
                        group: group,
                        progress: hasProgress
                            ? widget.objectivesProvider.missionProgress(
                                group.objective.id,
                              )
                            : null,
                        onTap: _openActivity,
                        xpByActivity: (id) => xpByActivity[id]?.total ?? 0,
                        liveStateByActivity: _liveStateFor,
                        availableParticipants: _availableParticipants,
                        interactive: !widget.readOnly,
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
                    child: Stack(
                      children: [
                        list,
                        // The pinged activity is below the fold: float a bar
                        // that scrolls to it. It latches hidden once the
                        // section has been seen (#8319).
                        if (pingedGroupIndex >= 0 && !_pingedSectionSeen)
                          Positioned(
                            bottom: 16.0,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: _PingedActivityBar(onTap: _scrollToPinged),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
          }
        },
      ),
    );
  }
}

/// The floating "pinged activity below" pill: bell + label + down arrow.
/// Tapping it scrolls the plan to the pinged activity's section.
class _PingedActivityBar extends StatelessWidget {
  final VoidCallback onTap;

  const _PingedActivityBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final onJoinable = ActivityPinState.joinable.onBodyColor(context);
    return Material(
      color: ActivityPinState.joinable.bodyColor(context),
      elevation: 4.0,
      borderRadius: BorderRadius.circular(24.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(24.0),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8.0,
            children: [
              Icon(Icons.notifications_outlined, size: 18.0, color: onJoinable),
              Text(
                L10n.of(context).pingedActivity,
                style: TextStyle(
                  color: onJoinable,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(Icons.arrow_downward, size: 18.0, color: onJoinable),
            ],
          ),
        ),
      ),
    );
  }
}

/// The course plan's failed-load state. A missing quest (#7479) offers an
/// admin the re-select CTA and tells everyone else the course is gone (#380).
@visibleForTesting
class QuestLoadErrorView extends StatelessWidget {
  final Object error;
  final bool showAddCourse;

  const QuestLoadErrorView(
    this.error, {
    super.key,
    required this.showAddCourse,
  });

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
                  L10n.of(context).missingCourseOutline,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              // The next step: an admin re-selects; a member can't, so they
              // are pointed at who can.
              Text(
                showAddCourse
                    ? L10n.of(context).pickNewCoursePlan
                    : L10n.of(context).askTeacherForNewCourse,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
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
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
