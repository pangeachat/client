import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:async/async.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The learner's XP in the current target language, split for the
/// next-Mission resolver (quests.instructions.md, "What fills a Mission"): a
/// construct use that names a room credits that room; a room-less use
/// (practice from the analytics page or a Mission's Practice) is kept by
/// word, and counts toward every Mission whose word list holds it — whether
/// or not the learner ever wrote it in a session (#9420 prototype).
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
  Map<String, int> _practiceXpByLemma = const {};

  /// XP credited to each room: everything the learner earned there.
  Map<String, int> get creditedXpByRoom => _creditedXpByRoom;

  /// The chat part of [creditedXpByRoom]: XP from messages the learner wrote
  /// in the room ([ConstructUseTypeEnum.isChatUse]).
  Map<String, int> get chatXpByRoom => _chatXpByRoom;

  /// The practice part of [creditedXpByRoom]: every other use in the room
  /// (message practice and the like). With [chatXpByRoom] it sums to
  /// [creditedXpByRoom].
  Map<String, int> get practiceXpByRoom => _practiceXpByRoom;

  /// Room-less practice XP by lowercased lemma — what a Mission's word list
  /// is credited from.
  Map<String, int> get practiceXpByLemma => _practiceXpByLemma;

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
      _publish(const {}, const {}, const {});
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
    for (final use in uses) {
      if (use.xp == 0) continue;
      final roomId = use.metadata.roomId;
      if (roomId == null) {
        final lemma = use.lemma.toLowerCase();
        byLemma[lemma] = (byLemma[lemma] ?? 0) + use.xp;
        continue;
      }
      final bucket = use.useType.isChatUse ? chatByRoom : practiceByRoom;
      bucket[roomId] = (bucket[roomId] ?? 0) + use.xp;
    }
    _publish(chatByRoom, practiceByRoom, byLemma);
  }

  void _publish(
    Map<String, int> chat,
    Map<String, int> practice,
    Map<String, int> byLemma,
  ) {
    final credited = Map<String, int>.of(chat);
    practice.forEach((room, xp) => credited[room] = (credited[room] ?? 0) + xp);
    if (mapEquals(credited, _creditedXpByRoom) &&
        mapEquals(chat, _chatXpByRoom) &&
        mapEquals(practice, _practiceXpByRoom) &&
        mapEquals(byLemma, _practiceXpByLemma)) {
      return;
    }
    _creditedXpByRoom = credited;
    _chatXpByRoom = chat;
    _practiceXpByRoom = practice;
    _practiceXpByLemma = byLemma;
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
  }) => _publish(xpByRoom, const {}, practiceXpByLemma);

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
