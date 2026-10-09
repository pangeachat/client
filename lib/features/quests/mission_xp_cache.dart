import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:async/async.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The learner's XP in the current target language, grouped two ways for the
/// next-Mission resolver (quests.instructions.md, "What fills a Mission"):
///
/// - [xpByRoom] — XP of every construct use that names the room it was earned
///   in, keyed by room id. A session room's XP rolls up to its activity and
///   from there to the Missions it satisfies.
/// - [practiceXpByLemma] — XP of every use that names NO room (standalone
///   practice), keyed by lower-cased lemma. It reaches a Mission through the
///   Mission's target vocabulary.
///
/// The two are a partition of the learner's uses, so no XP is counted twice.
/// The lemma route is a stopgap (#9420): a practice use carries no record of
/// the Mission it was launched for, and tagging it would change the stored
/// construct-use schema, which this draft deliberately leaves alone. Until a
/// use records its Mission, practising a Mission's words anywhere counts
/// toward it, and a word two Missions share credits both.
///
/// One process-wide instance, refreshed from the local analytics database on
/// construct updates and language changes, rate-limited like the sync-tick
/// resolve. Consumers read the maps synchronously and listen for changes; a
/// read before the first refresh lands sees empty maps and resolves every
/// Mission as unstarted, which is the same fail-soft the resolver already
/// has for a missing outline.
class MissionXpCache extends ChangeNotifier {
  MissionXpCache._();
  static final MissionXpCache instance = MissionXpCache._();

  Map<String, int> _xpByRoom = const {};
  Map<String, int> _practiceXpByLemma = const {};

  Map<String, int> get xpByRoom => _xpByRoom;
  Map<String, int> get practiceXpByLemma => _practiceXpByLemma;

  bool _wired = false;
  StreamSubscription? _sub;
  Future<void>? _inflight;
  bool _dirty = false;

  /// Subscribe to the analytics streams and take the first read. Idempotent;
  /// every consumer calls it, and the first one to run wires the cache. A
  /// no-op before the Pangea controller exists (widget tests).
  void ensureWired() {
    if (_wired || !MatrixState.isPangeaControllerInitialized) return;
    final controller = MatrixState.pangeaController;
    _sub = StreamGroup.merge([
      controller
          .matrixState
          .analyticsDataService
          .updateDispatcher
          .constructUpdateStream
          .stream,
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
    final List<OneConstructUse> uses;
    try {
      uses = await controller.matrixState.analyticsDataService.getUses(
        language,
      );
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
    final byRoom = <String, int>{};
    final byLemma = <String, int>{};
    for (final use in uses) {
      if (use.xp == 0) continue;
      final roomId = use.metadata.roomId;
      if (roomId != null) {
        byRoom[roomId] = (byRoom[roomId] ?? 0) + use.xp;
      } else {
        final lemma = use.lemma.toLowerCase();
        byLemma[lemma] = (byLemma[lemma] ?? 0) + use.xp;
      }
    }
    _publish(byRoom, byLemma);
  }

  void _publish(Map<String, int> byRoom, Map<String, int> byLemma) {
    if (mapEquals(byRoom, _xpByRoom) &&
        mapEquals(byLemma, _practiceXpByLemma)) {
      return;
    }
    _xpByRoom = byRoom;
    _practiceXpByLemma = byLemma;
    // A loader wires this cache from its constructor, which a context bar
    // runs inside a build; notifying there would mark its builders dirty
    // mid-build. The microtask runs once the build has unwound.
    scheduleMicrotask(notifyListeners);
  }

  /// Test seam: set the maps directly, bypassing the analytics read.
  @visibleForTesting
  void seed({
    Map<String, int> xpByRoom = const {},
    Map<String, int> practiceXpByLemma = const {},
  }) => _publish(xpByRoom, practiceXpByLemma);

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
