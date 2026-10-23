import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The learner's XP in the current target language, split for the
/// next-Mission resolver (quests.instructions.md, "What fills a Mission"): a
/// construct use that names a room credits that room; a room-less use
/// (practice from the analytics page or a Mission's Practice) is kept by
/// word, and counts toward every Mission whose word list holds it — whether
/// or not the learner ever wrote it in a session (#9420).
///
/// One process-wide instance, refreshed from the local analytics database on
/// construct updates and language changes, rate-limited like the sync-tick
/// resolve. Consumers read the map synchronously and listen for changes; a
/// read before the first refresh lands sees an empty map and resolves every
/// Mission as unstarted, which is the same fail-soft the resolver already
/// has for a missing outline.
class MissionXpCache extends ChangeNotifier {
  MissionXpCache._();
  static final MissionXpCache instance = MissionXpCache._();

  Map<String, int> _creditedXpByRoom = const {};
  Map<String, int> _chatXpByRoom = const {};
  Map<String, int> _speakingXpByRoom = const {};
  Map<String, int> _practiceXpByRoom = const {};
  Map<String, int> _practiceXpByLemma = const {};
  Map<String, Map<LearningSkillsEnum, int>> _skillXpByRoom = const {};
  Map<String, Map<LearningSkillsEnum, int>> _skillXpByLemma = const {};

  /// XP credited to each room: everything the learner earned there.
  Map<String, int> get creditedXpByRoom => _creditedXpByRoom;

  /// The chat part of [creditedXpByRoom]: XP from messages the learner wrote
  /// in the room ([ConstructUseTypeEnum.isChatUse]).
  Map<String, int> get chatXpByRoom => _chatXpByRoom;

  /// The speaking part of [creditedXpByRoom]: XP from the learner's voice
  /// messages and calls in the room ([LearningSkillsEnum.speaking] uses).
  Map<String, int> get speakingXpByRoom => _speakingXpByRoom;

  /// The practice part of [creditedXpByRoom]: every other use in the room
  /// (message practice and the like). With [chatXpByRoom] and
  /// [speakingXpByRoom] it sums to [creditedXpByRoom].
  Map<String, int> get practiceXpByRoom => _practiceXpByRoom;

  /// Room-less practice XP by lowercased lemma — what a Mission's word list
  /// is credited from.
  Map<String, int> get practiceXpByLemma => _practiceXpByLemma;

  /// [creditedXpByRoom] split by the skill each use exercises
  /// ([ConstructUseTypeEnum.skillsEnumType]) — writing, speaking, listening,
  /// reading — for a Mission's detail page (#9559).
  Map<String, Map<LearningSkillsEnum, int>> get skillXpByRoom => _skillXpByRoom;

  /// [practiceXpByLemma] split the same way.
  Map<String, Map<LearningSkillsEnum, int>> get skillXpByLemma =>
      _skillXpByLemma;

  bool _wired = false;
  StreamSubscription? _sub;
  StreamSubscription? _languageSub;
  Future<void>? _inflight;
  bool _dirty = false;

  bool _loading = true;

  /// The current language's XP hasn't been read yet (#9559): from start-up,
  /// and again from the moment the learner switches language, until that
  /// language's first read lands. Progress surfaces shimmer meanwhile rather
  /// than show the empty or half-read maps as if they were final. Ordinary
  /// re-reads as XP lands don't set it, so nothing flickers during play.
  /// Only once wired: an unwired cache has no read coming to clear it.
  bool get loading => _loading && _wired;

  void _setLoading(bool value) {
    if (_loading == value) return;
    _loading = value;
    // A notifier fired inside a build marks its listeners dirty mid-build;
    // the microtask runs once the build has unwound (as [_publish] does).
    scheduleMicrotask(notifyListeners);
  }

  /// Subscribe to the analytics streams and take the first read. Idempotent;
  /// every consumer calls it, and the first one to run wires the cache. A
  /// no-op before the Pangea controller or the account's analytics service
  /// exists (widget tests); the next consumer retries.
  void ensureWired() {
    if (_wired || !MatrixState.isPangeaControllerInitialized) return;
    final controller = MatrixState.pangeaController;
    // Never the trigger for analytics initialisation: the active-client
    // getter creates the service on a miss and its constructor starts init.
    final analytics = controller.matrixState.analyticsServiceIfExists;
    if (analytics == null) return;
    _sub = StreamGroup.merge([
      analytics.updateDispatcher.constructUpdateStream.stream,
      controller.userController.languageStream.stream,
    ]).rateLimit(const Duration(seconds: 2)).listen((_) => refresh());
    // Unthrottled: the switch is loading the moment it happens, even though
    // the re-read itself waits on the rate limit above.
    // A read already in flight is for the old language: run once more after
    // it, so it can't clear the flag with the old language's maps.
    _languageSub = controller.userController.languageStream.stream.listen((_) {
      _setLoading(true);
      if (_inflight != null) _dirty = true;
    });
    // Marked wired only once the subscription holds, so a throw above leaves
    // the next caller to try again rather than a cache that never reads.
    _wired = true;
    refresh();
  }

  /// Re-read the learner's uses and regroup. A refresh asked for while one is
  /// in flight runs once more after it, so the last update is never lost.
  Future<void> refresh() {
    final inflight = _inflight;
    if (inflight != null) {
      _dirty = true;
      return inflight;
    }
    return _inflight = _runRefresh();
  }

  Future<void> _runRefresh() async {
    var settled = true;
    try {
      settled = await _refresh();
    } catch (e, s) {
      // The previous maps stand and the meters stop waiting; the failure is
      // reported rather than left to wedge the cache in flight.
      ErrorHandler.logError(e: e, s: s, data: {}, level: SentryLevel.warning);
    } finally {
      _inflight = null;
      if (_dirty) {
        _dirty = false;
        refresh();
      } else if (settled) {
        _setLoading(false);
      }
    }
  }

  /// Re-read and publish. True when the maps now reflect the current
  /// language, or when nothing more is coming (no language, analytics that
  /// failed to start, a failed read) — either way the surfaces stop
  /// shimmering; false while analytics is still starting, whose first
  /// construct update calls [refresh] again.
  Future<bool> _refresh() async {
    final controller = MatrixState.pangeaController;
    final language = controller.userController.userL2?.langCodeShort;
    if (language == null) {
      _publish(const {}, const {}, const {}, const {}, const {}, const {});
      return true;
    }
    final analytics = controller.matrixState.analyticsServiceIfExists;
    // silent-ok: analytics that failed to start reports itself; the meters
    // fall back to what they hold rather than shimmering forever.
    if (analytics != null && analytics.hasInitError) return true;
    // A read before init completes would start it from here; init's own
    // first construct update calls [refresh] once it is done.
    if (analytics == null || !analytics.initCompleter.isCompleted) {
      return false;
    }
    final List<OneConstructUse> uses;
    try {
      uses = await analytics.getUses(language);
    } catch (e, s) {
      // The previous maps stand; a failed read must not blank every Mission
      // meter, but it must be seen (error-handling.instructions.md).
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'language': language},
        level: SentryLevel.warning,
      );
      return true;
    }
    // The learner switched language while this read ran: its maps are the
    // old language's. Read again rather than publish them.
    if (controller.userController.userL2?.langCodeShort != language) {
      _dirty = true;
      return false;
    }
    final chatByRoom = <String, int>{};
    final speakingByRoom = <String, int>{};
    final practiceByRoom = <String, int>{};
    final byLemma = <String, int>{};
    final skillByRoom = <String, Map<LearningSkillsEnum, int>>{};
    final skillByLemma = <String, Map<LearningSkillsEnum, int>>{};
    for (final use in uses) {
      if (use.xp == 0) continue;
      final roomId = use.metadata.roomId;
      if (roomId == null) {
        final lemma = QuestObjectiveGroup.lemmaKey(use.lemma);
        byLemma[lemma] = (byLemma[lemma] ?? 0) + use.xp;
        _addSkill(skillByLemma, lemma, use);
        continue;
      }
      _addSkill(skillByRoom, roomId, use);
      final bucket = use.useType.isChatUse
          ? chatByRoom
          : use.useType.skillsEnumType == LearningSkillsEnum.speaking
          ? speakingByRoom
          : practiceByRoom;
      bucket[roomId] = (bucket[roomId] ?? 0) + use.xp;
    }
    _publish(
      chatByRoom,
      speakingByRoom,
      practiceByRoom,
      byLemma,
      skillByRoom,
      skillByLemma,
    );
    return true;
  }

  /// Adds [use]'s XP to its skill under [key] in [into].
  static void _addSkill(
    Map<String, Map<LearningSkillsEnum, int>> into,
    String key,
    OneConstructUse use,
  ) {
    final skills = into[key] ??= {};
    final skill = use.useType.skillsEnumType;
    skills[skill] = (skills[skill] ?? 0) + use.xp;
  }

  void _publish(
    Map<String, int> chat,
    Map<String, int> speaking,
    Map<String, int> practice,
    Map<String, int> byLemma,
    Map<String, Map<LearningSkillsEnum, int>> skillByRoom,
    Map<String, Map<LearningSkillsEnum, int>> skillByLemma,
  ) {
    final credited = Map<String, int>.of(chat);
    for (final part in [speaking, practice]) {
      part.forEach((room, xp) => credited[room] = (credited[room] ?? 0) + xp);
    }
    if (mapEquals(chat, _chatXpByRoom) &&
        mapEquals(speaking, _speakingXpByRoom) &&
        mapEquals(practice, _practiceXpByRoom) &&
        mapEquals(byLemma, _practiceXpByLemma) &&
        const DeepCollectionEquality().equals(skillByRoom, _skillXpByRoom) &&
        const DeepCollectionEquality().equals(skillByLemma, _skillXpByLemma)) {
      return;
    }
    _creditedXpByRoom = credited;
    _chatXpByRoom = chat;
    _speakingXpByRoom = speaking;
    _practiceXpByRoom = practice;
    _practiceXpByLemma = byLemma;
    _skillXpByRoom = skillByRoom;
    _skillXpByLemma = skillByLemma;
    // A loader wires this cache from its constructor, which a context bar
    // runs inside a build; notifying there would mark its builders dirty
    // mid-build. The microtask runs once the build has unwound.
    scheduleMicrotask(notifyListeners);
  }

  /// Test seam: set the inputs directly, bypassing the analytics read.
  @visibleForTesting
  void seed({
    Map<String, int> xpByRoom = const {},
    Map<String, int> practiceXpByLemma = const {},
  }) {
    // Seeded maps are the whole read: nothing is loading.
    _loading = false;
    _publish(
      xpByRoom,
      const {},
      const {},
      practiceXpByLemma,
      const {},
      const {},
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _languageSub?.cancel();
    super.dispose();
  }
}
