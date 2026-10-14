import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:async/async.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The learner's XP in the current target language, credited per room for
/// the next-Mission resolver (quests.instructions.md, "What fills a Mission"):
/// a construct use that names a room credits that room; a room-less use
/// (practice from the analytics page) credits every room in whose messages
/// the learner wrote the word, by lemma (org activities doc, "Practice
/// credit"). A word written in two sessions credits both, so the per-room
/// sums can exceed the learner's total; each is what that session shows and
/// what its activity rolls up.
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
  Map<String, int> _practiceXpByRoom = const {};

  /// XP credited to each room: the XP earned there plus the room-less
  /// practice XP on words the learner wrote there.
  Map<String, int> get creditedXpByRoom => _creditedXpByRoom;

  /// The chat part of [creditedXpByRoom]: XP from messages the learner wrote
  /// in the room ([ConstructUseTypeEnum.isChatUse]).
  Map<String, int> get chatXpByRoom => _chatXpByRoom;

  /// The practice part of [creditedXpByRoom]: every other use in the room
  /// (message practice and the like) plus the room-less practice credited to
  /// it by word. With [chatXpByRoom] it sums to [creditedXpByRoom].
  Map<String, int> get practiceXpByRoom => _practiceXpByRoom;

  bool _wired = false;
  StreamSubscription? _sub;
  Future<void>? _inflight;
  bool _dirty = false;

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
    return _inflight = _refresh().whenComplete(() {
      _inflight = null;
      if (_dirty) {
        _dirty = false;
        refresh();
      }
    });
  }

  Future<void> _refresh() async {
    final controller = MatrixState.pangeaController;
    final language = controller.userController.userL2?.langCodeShort;
    if (language == null) {
      _publish(const {}, const {});
      return;
    }
    final analytics = controller.matrixState.analyticsServiceIfExists;
    // A read before init completes would start it from here; init's own
    // first construct update calls [refresh] once it is done.
    if (analytics == null || !analytics.initCompleter.isCompleted) return;
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
      return;
    }
    final chatByRoom = <String, int>{};
    final practiceByRoom = <String, int>{};
    final byLemma = <String, int>{};
    final roomsByLemma = <String, Set<String>>{};
    for (final use in uses) {
      final roomId = use.metadata.roomId;
      final lemma = use.lemma.toLowerCase();
      if (roomId == null) {
        if (use.xp != 0) byLemma[lemma] = (byLemma[lemma] ?? 0) + use.xp;
        continue;
      }
      if (use.xp != 0) {
        final bucket = use.useType.isChatUse ? chatByRoom : practiceByRoom;
        bucket[roomId] = (bucket[roomId] ?? 0) + use.xp;
      }
      // Only words the learner wrote: a word they read or heard in a room
      // is not theirs to be credited for practising.
      if (use.useType.sentByUser) {
        (roomsByLemma[lemma] ??= {}).add(roomId);
      }
    }
    _publish(chatByRoom, credit(practiceByRoom, byLemma, roomsByLemma));
  }

  /// Chat XP per room plus the room-less practice XP on every word the
  /// learner wrote there (org activities doc, "Practice credit"). Pure.
  @visibleForTesting
  static Map<String, int> credit(
    Map<String, int> xpByRoom,
    Map<String, int> practiceXpByLemma,
    Map<String, Set<String>> roomsByLemma,
  ) {
    final credited = Map<String, int>.of(xpByRoom);
    for (final entry in practiceXpByLemma.entries) {
      for (final roomId in roomsByLemma[entry.key] ?? const <String>{}) {
        credited[roomId] = (credited[roomId] ?? 0) + entry.value;
      }
    }
    return credited;
  }

  void _publish(Map<String, int> chat, Map<String, int> practice) {
    final credited = Map<String, int>.of(chat);
    practice.forEach((room, xp) => credited[room] = (credited[room] ?? 0) + xp);
    if (mapEquals(credited, _creditedXpByRoom) &&
        mapEquals(chat, _chatXpByRoom) &&
        mapEquals(practice, _practiceXpByRoom)) {
      return;
    }
    _creditedXpByRoom = credited;
    _chatXpByRoom = chat;
    _practiceXpByRoom = practice;
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
    Map<String, Set<String>> roomsByLemma = const {},
  }) => _publish(xpByRoom, credit(const {}, practiceXpByLemma, roomsByLemma));

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
