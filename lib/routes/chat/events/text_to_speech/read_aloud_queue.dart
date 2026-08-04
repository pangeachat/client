/// Single-slot playback scheduling for automatic message read-aloud, with no
/// dependency on Matrix, `flutter_tts`, or app state, so it is unit-testable.
///
/// At most one item waits while another is being spoken, and a newer arrival
/// replaces the waiting one rather than queueing behind it. That keeps playback
/// at most one item behind the conversation, so what the learner hears is still
/// on screen.
///
/// See client/.github/instructions/message-read-aloud.instructions.md
class ReadAloudQueue<T> {
  ReadAloudQueue({required this.speak, required this.canPlay});

  /// Plays [T], completing when playback finishes or is stopped.
  final Future<void> Function(T) speak;

  /// Whether playback is currently allowed. Re-checked before each item, so a
  /// state change during playback silences the waiting item too.
  final bool Function() canPlay;

  T? _waiting;
  bool _isSpeaking = false;

  /// Incremented whenever playback is superseded or stopped, so a finishing
  /// utterance can tell whether it is still the current one before it drains
  /// the waiting slot.
  int _generation = 0;

  bool get isSpeaking => _isSpeaking;
  bool get hasWaiting => _waiting != null;

  void add(T item) {
    if (!canPlay()) return;
    if (_isSpeaking) {
      _waiting = item;
      return;
    }
    _play(item);
  }

  /// Drops the waiting item and ends playback in progress. The waiting item is
  /// not held for later, since playing it once the interruption passes would
  /// arrive with no connection to what is on screen.
  void clear() {
    _waiting = null;
    if (!_isSpeaking) return;
    _generation++;
    _isSpeaking = false;
  }

  Future<void> _play(T item) async {
    final generation = ++_generation;
    _isSpeaking = true;

    try {
      await speak(item);
    } finally {
      if (generation == _generation) _isSpeaking = false;
    }

    if (generation != _generation) return;

    final next = _waiting;
    _waiting = null;
    if (next == null || !canPlay()) return;
    await _play(next);
  }
}
