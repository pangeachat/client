import 'dart:async';

/// How one device utterance ended, from the controller's point of view.
enum TtsDeviceOutcome {
  /// The engine started speaking. It may then have finished, been cut off by a
  /// stop, or been interrupted by something outside the app — in every case
  /// the learner heard audio, so the interval that was open is listening and
  /// there is nothing to rescue.
  played,

  /// Stopped by the app before the engine started: the learner tapped stop, a
  /// later request superseded it, or its widget went away. Silence was asked
  /// for, so nothing is rescued.
  cancelled,

  /// Never produced audio and nobody asked it to stop: the engine reported an
  /// error, the plugin returned without ever starting, a stale cancel event
  /// from a previous utterance landed on this one, or the engine never
  /// reported a start within [TtsDeviceUtterance.startTimeout]. Nothing was
  /// heard and the request is still wanted, so it is eligible for a backend
  /// rescue.
  failed,
}

/// Tracks a single `flutter_tts.speak` from the moment the plugin is asked to
/// speak until it is known to have ended, and says how.
///
/// Why this exists: with `awaitSpeakCompletion(true)` the plugin's `speak`
/// future resolves only when the engine reports the utterance *finished*. It
/// never resolves on the web when the utterance errors — the web plugin nulls
/// its completer in `onError` without completing it — and Chrome reports every
/// interruption as an error (`interrupted`), so the next tap's `stop()` left
/// the previous request awaiting forever: its `finally` never ran, its
/// listening measurement was never closed, and its own `onStop` never fired.
/// iOS drops the pending result on `stop` and hangs the same way. So the
/// controller no longer trusts the speak future alone: the plugin's start,
/// completion, cancel and error handlers all feed this object, and whichever
/// signal arrives first settles it.
///
/// One rule decides the outcome of every end signal, whatever its shape:
/// audio was heard iff the engine reported a start; otherwise it is a cancel
/// iff the app asked for the stop, and a failure if nobody did. Which callback
/// carried the news (completion, cancel, error, the speak future, a timeout)
/// does not change what the learner heard.
///
/// Pure Dart with no plugin dependency, so the outcome rules are unit-tested
/// without a platform channel. See word-text-to-speech.instructions.md,
/// "Failure handling".
class TtsDeviceUtterance {
  TtsDeviceUtterance({required this.startTimeout});

  /// How long the engine has to report a start before the utterance is given
  /// up. Guards against a plugin whose state is stuck (the web plugin's
  /// `_speak` silently no-ops while it still believes a previous utterance is
  /// playing, so no event ever comes) and against engines that fail without
  /// reporting it.
  final Duration startTimeout;

  final Completer<TtsDeviceOutcome> _outcome = Completer<TtsDeviceOutcome>();
  final Completer<void> _engineEnded = Completer<void>();
  Timer? _watchdog;

  /// The engine reported that speech began.
  bool started = false;

  /// The app asked the engine to stop this utterance. Distinguishes a cancel
  /// the learner (or a superseding request) asked for from one nobody did — a
  /// stale event from the previous utterance, or an engine giving up.
  bool stopRequested = false;

  /// Resolves once, with how the utterance ended.
  Future<TtsDeviceOutcome> get outcome => _outcome.future;

  bool get isSettled => _outcome.isCompleted;

  /// Resolves when the engine itself reported an end (completion, cancel or
  /// error) — as opposed to [outcome], which may settle earlier on the
  /// watchdog or the speak future. `stop()` waits on this so the next
  /// utterance is not issued while the plugin still believes this one is
  /// playing.
  Future<void> get engineEnded => _engineEnded.future;

  bool get engineHasEnded => _engineEnded.isCompleted;

  /// Arm the start watchdog. Call right before asking the plugin to speak.
  void arm() {
    _watchdog?.cancel();
    _watchdog = Timer(startTimeout, () {
      if (!started) _settle();
    });
  }

  /// Release the watchdog. Idempotent; safe after settling.
  void dispose() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  /// The app is about to ask the engine to stop this utterance.
  void requestStop() => stopRequested = true;

  /// The app asked the engine to stop and it never confirmed. Settles on what
  /// is known rather than waiting forever.
  void onStopUnconfirmed() => _settle();

  /// Plugin `startHandler`.
  void onEngineStart() {
    started = true;
  }

  /// Plugin `completionHandler`.
  void onEngineComplete() {
    // The ONLY positive evidence that the utterance reached its end.
    _engineReportedComplete = true;
    _engineEnd();
  }

  /// Plugin `cancelHandler` — the engine confirmed a stop.
  void onEngineCancel() {
    _engineReportedComplete = false;
    _engineEnd();
  }

  /// Plugin `errorHandler`. The Web Speech API reports interruptions here too
  /// (`interrupted` after speech began, `canceled` before); the message does
  /// not matter, only whether a start preceded it and whether a stop was asked.
  void onEngineError(dynamic message) {
    // Chrome reports an interruption here. Whatever ended this utterance, it
    // was not a clean finish.
    _engineReportedComplete = false;
    _engineEnd();
  }

  /// The plugin's `speak` future resolved. On native this means finished (or,
  /// on Android, stopped); on the web it means the engine fired `end`. Either
  /// way audio was heard only if a start was reported first — a completion
  /// with no start is the previous utterance's `end` event landing on this
  /// one, which never spoke.
  void onSpeakReturned() => _settle();

  /// The plugin's `speak` future threw.
  void onSpeakThrew() => _settle(TtsDeviceOutcome.failed);

  /// Whether this utterance ran to its end.
  ///
  /// [TtsDeviceOutcome.played] deliberately does NOT answer this: for listening
  /// minutes an utterance that was cut off still counts, because the learner
  /// heard the part that played. Word-level exposure is the opposite — it is
  /// all-or-nothing per lemma, and a read stopped after two words did not
  /// expose the learner to the rest of the sentence.
  ///
  /// **Positive evidence only.** This is not "ended and we did not stop it":
  /// an utterance cut short by a phone call, by audio focus moving to another
  /// app, or by the browser cancelling `speechSynthesis` ends with no stop of
  /// ours, and defining completion by the absence of our own stop would count
  /// every one of those as fully heard. It requires the engine to have
  /// reported a completion.
  ///
  /// The cost is under-counting on a platform whose plugin never fires
  /// `completionHandler` — exposure would simply not be recorded there. That
  /// is the right direction to fail for a research signal: a gap is visible,
  /// a phantom is not.
  ///
  /// Captured at settle time rather than derived on read: [stopRequested] is
  /// mutable, and a LATER request's stop must not retroactively reclassify an
  /// utterance that had already finished.
  bool get playedToEnd => _playedToEnd;
  bool _playedToEnd = false;

  /// Whether the engine reported this utterance COMPLETING, as opposed to
  /// ending some other way.
  bool _engineReportedComplete = false;

  TtsDeviceOutcome get _endedOutcome {
    if (started) return TtsDeviceOutcome.played;
    return stopRequested ? TtsDeviceOutcome.cancelled : TtsDeviceOutcome.failed;
  }

  void _engineEnd() {
    if (!_engineEnded.isCompleted) _engineEnded.complete();
    _settle();
  }

  void _settle([TtsDeviceOutcome? outcome]) {
    dispose();
    if (_outcome.isCompleted) return;
    // A clean finish is: audio started, the engine said it completed, and
    // nothing asked it to stop. An explicit outcome is only ever passed for a
    // failure, so it disqualifies too.
    _playedToEnd =
        outcome == null && started && !stopRequested && _engineReportedComplete;
    _outcome.complete(outcome ?? _endedOutcome);
  }
}
