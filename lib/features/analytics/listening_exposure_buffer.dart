import 'package:flutter/foundation.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';

/// Accumulates listening exposure into per-lemma buckets, so a window's worth
/// of hearings costs one row rather than one row per word heard.
///
/// **Why buckets at all.** Exposure fires on every read-aloud surface, and
/// nothing in the analytics store ever prunes or compacts uses — a heavy
/// listener would otherwise bank hundreds of thousands of near-empty rows a
/// year on a list that is re-parsed per construct on every sync. See
/// analytics-system.instructions.md.
///
/// **Why the window is short.** Construct-use timestamps double as
/// corroboration anchors for engagement spans, matched within ±10 minutes with
/// no type filter, so a bucket vouches for activity only around the instant it
/// carries. A day-long bucket would carry one anchor and stop vouching for the
/// rest of the day — which bites hardest in the passive listening session,
/// where exposure rows are the only anchors a learner has. [window] therefore
/// stays well inside the corroboration window.
///
/// **Buckets are per language, and that is load-bearing.** A stored use carries
/// no language of its own, so a hearing filed into the wrong language's room is
/// indistinguishable from a real one afterwards. Read-aloud is gated on the L2,
/// but voice messages and word taps inside a message are not — a multilingual
/// room speaks whatever was written. So the language travels with the
/// recording, [drain] hands back only the language it was asked for, and there
/// is no code path that can file a use under a language it was not spoken in.
/// See analytics-system.instructions.md (Per-Language Isolation).
///
/// Every entry point here is synchronous and allocation-only: this runs on the
/// playback path and must be invisible to the learner. Delivery happens later,
/// when [drain] is called from the analytics heartbeat.
class ListeningExposureBuffer {
  /// How long a bucket stays open. Five minutes matches the analytics
  /// heartbeat, so in practice a bucket is closed by the flush that sends it
  /// and this bound only bites when the heartbeat is not running — on mobile,
  /// a suspended timer in the background. It exists so the ±10 minute
  /// corroboration invariant holds regardless of timer behaviour.
  static const Duration window = Duration(minutes: 5);

  /// The most languages held at once, so a buffer cannot grow one bucket set
  /// per language heard. Exposure in a language that never becomes the
  /// learner's L2 is never drained by anyone, so without this it would
  /// accumulate for the life of the session. Least-recently-heard is evicted.
  static const int maxLanguages = 8;

  /// The most rows held per language.
  ///
  /// A drain that cannot persist puts its rows back, and a language nobody
  /// drains closes windows forever, so both paths need a ceiling. Past it the
  /// OLDEST rows are dropped: exposure is a 0-XP research signal, and losing
  /// the start of a long outage beats growing memory on a device until it is
  /// killed.
  static const int maxHeldRows = 5000;

  ListeningExposureBuffer({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// One buffer per logged-in account. Exposure is recorded from static
  /// playback paths that have no handle on the account's analytics service, and
  /// attributing a hearing to the wrong account is worse than losing it, so the
  /// account is resolved at record time rather than captured.
  static final Map<String, ListeningExposureBuffer> _byAccount = {};

  /// The buffer for [userId], created on first use. Returns none for an unknown
  /// account (empty userId).
  static ListeningExposureBuffer? forAccount(String userId) {
    if (userId.isEmpty) return null;
    return _byAccount.putIfAbsent(userId, ListeningExposureBuffer.new);
  }

  /// Drops [userId]'s buffer. Call AFTER a final drain: whatever is still held
  /// here is discarded, not sent.
  static void disposeAccount(String userId) => _byAccount.remove(userId);

  /// Seeds a buffer for [userId] (tests only).
  @visibleForTesting
  static void debugPutAccount(String userId, ListeningExposureBuffer buffer) =>
      _byAccount[userId] = buffer;

  /// Clears the app-global registry so it cannot leak between tests.
  @visibleForTesting
  static void debugResetAccounts() => _byAccount.clear();

  final DateTime Function() _now;

  /// One bucket set per language. Insertion-ordered and re-inserted on every
  /// touch, so the FIRST key is the least recently heard language.
  final Map<String, _LanguageBuckets> _byLanguage = {};

  /// The key a language is held under: the base subtag, lowercased, so `es-MX`
  /// and `es` are one language. Regional variants do not partition analytics —
  /// the rest of the app resolves them to the base language too.
  static String languageKey(String langCode) =>
      langCode.split('-').first.trim().toLowerCase();

  bool get isEmpty => _byLanguage.values.every((b) => b.isEmpty);

  /// Exposures held across every language, counting occurrences not rows.
  int get pendingExposures =>
      _byLanguage.values.fold<int>(0, (sum, b) => sum + b.pendingExposures);

  /// Exposures held for [langCode] alone.
  int pendingExposuresFor(String langCode) =>
      _byLanguage[languageKey(langCode)]?.pendingExposures ?? 0;

  /// The languages this buffer is holding exposure for.
  Iterable<String> get heldLanguages => List.unmodifiable(_byLanguage.keys);

  /// Records that [constructs] were heard once each, in [langCode].
  ///
  /// [langCode] is required and comes from whatever knows what was actually
  /// spoken — the language handed to the TTS engine, or the transcript's own.
  /// It is never inferred from the learner's current L2: read-aloud is L2-gated
  /// but voice messages and word taps in a message are not, so a multilingual
  /// room speaks whatever was written.
  ///
  /// Callers pass only vocab constructs for tokens whose lemma is worth saving;
  /// this does not re-filter, because the caller is the only thing that knows
  /// which tokens its utterance actually covered.
  void record(
    Iterable<ConstructIdentifier> constructs, {
    required String langCode,
  }) {
    final key = languageKey(langCode);
    if (key.isEmpty) return;
    // Remove-then-insert keeps insertion order meaning least-recently-heard.
    final buckets = _byLanguage.remove(key) ?? _LanguageBuckets();
    _byLanguage[key] = buckets;
    buckets.record(constructs, _now());
    _evictStaleLanguages();
  }

  /// Closes and returns everything waiting to be written for [langCode].
  ///
  /// Only that language: a drain files its rows under the language it asked
  /// for, so handing back another language's rows is exactly the mislabeling
  /// this buffer exists to prevent.
  ///
  /// That language is empty afterwards — a drained row is the caller's
  /// responsibility, so a caller that fails to persist loses the window rather
  /// than double-counting it, which is what [restore] is for.
  List<OneConstructUse> drain(String langCode) {
    final buckets = _byLanguage[languageKey(langCode)];
    if (buckets == null) return const [];
    return buckets.drain();
  }

  /// Puts [langCode]'s drained rows back after a failed write.
  void restore(String langCode, List<OneConstructUse> uses) {
    if (uses.isEmpty) return;
    final key = languageKey(langCode);
    if (key.isEmpty) return;
    (_byLanguage[key] ??= _LanguageBuckets()).restore(uses);
  }

  /// Drops the least-recently-heard languages past [maxLanguages].
  ///
  /// Exposure in a language that never becomes the learner's L2 is never
  /// drained by anyone, so without this a session in a multilingual room grows
  /// a bucket set per language heard and never gives any of them back.
  void _evictStaleLanguages() {
    while (_byLanguage.length > maxLanguages) {
      _byLanguage.remove(_byLanguage.keys.first);
    }
  }
}

/// The buckets held for ONE language.
class _LanguageBuckets {
  /// Open buckets, keyed by construct. Insertion-ordered, so a drain returns
  /// exposure in the order the learner first heard each lemma in this window.
  final Map<ConstructIdentifier, _ExposureBucket> _open = {};

  /// Buckets closed by the window bound and waiting for the next drain.
  final List<OneConstructUse> _closed = [];

  /// When the oldest currently-open bucket started.
  DateTime? _openedAt;

  bool get isEmpty => _open.isEmpty && _closed.isEmpty;

  int get pendingExposures =>
      _closed.fold<int>(0, (sum, use) => sum + use.count) +
      _open.values.fold<int>(0, (sum, bucket) => sum + bucket.count);

  void record(Iterable<ConstructIdentifier> constructs, DateTime at) {
    _closeIfWindowElapsed(at);
    for (final id in constructs) {
      final bucket = _open[id];
      if (bucket == null) {
        _open[id] = _ExposureBucket(count: 1, last: at);
      } else {
        bucket.count += 1;
        bucket.last = at;
      }
    }
    if (_open.isNotEmpty) _openedAt ??= at;
  }

  List<OneConstructUse> drain() {
    _closeOpen();
    final drained = List<OneConstructUse>.unmodifiable(_closed);
    _closed.clear();
    return drained;
  }

  /// Restored rows go to the FRONT: they are older than anything recorded
  /// since, and [_closed] is kept chronological.
  void restore(List<OneConstructUse> uses) {
    _closed.insertAll(0, uses);
    _bound();
  }

  void _closeIfWindowElapsed(DateTime at) {
    final openedAt = _openedAt;
    if (openedAt == null) return;
    if (at.difference(openedAt) < ListeningExposureBuffer.window) return;
    _closeOpen();
  }

  void _closeOpen() {
    for (final entry in _open.entries) {
      _closed.add(_toUse(entry.key, entry.value));
    }
    _open.clear();
    _openedAt = null;
    // Bound HERE too, not only on restore: a language that is never drained —
    // because it is not the learner's L2 — closes windows forever otherwise.
    _bound();
  }

  void _bound() {
    final overflow = _closed.length - ListeningExposureBuffer.maxHeldRows;
    if (overflow > 0) _closed.removeRange(0, overflow);
  }

  /// One bucket as it goes to storage.
  ///
  /// The timestamp is the bucket's LAST exposure — a real instant inside the
  /// bucket, never a synthetic boundary, so the row cannot vouch for activity
  /// at a time the learner was not active.
  ///
  /// No room id and no event id, ever. The listening lane drops both at the
  /// point of collection because a per-student record of which peers a learner
  /// attends to is a social-graph fact about a third party, and a lemma-level
  /// record derived from someone else's message would reintroduce exactly that
  /// with content attached.
  ///
  /// No form either: a bucket spans however many surface forms of the lemma
  /// were heard in the window, so there is no one form it could honestly name.
  static OneConstructUse _toUse(
    ConstructIdentifier id,
    _ExposureBucket bucket,
  ) {
    return OneConstructUse(
      useType: ConstructUseTypeEnum.hrd,
      lemma: id.lemma,
      constructType: id.type,
      category: id.category,
      form: null,
      xp: ConstructUseTypeEnum.hrd.pointValue,
      count: bucket.count,
      metadata: ConstructUseMetaData(
        roomId: null,
        eventId: null,
        timeStamp: bucket.last,
      ),
    );
  }
}

class _ExposureBucket {
  _ExposureBucket({required this.count, required this.last});

  int count;
  DateTime last;
}
