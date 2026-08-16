import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/dosage/dosage_audio_event.dart';
import 'package:fluffychat/features/dosage/dosage_playback_meter.dart';

/// Elapsed-playback accounting ([DosagePlaybackMeter]).
///
/// The magnitude every listening counter is built from, so its failure modes are
/// the counters' failure modes: a paused playback banking time it did not play,
/// a silent TTS exit banking a near-zero interval as if audio was heard, and one
/// playback emitted twice because completion and dispose both closed it.
void main() {
  late DateTime clock;
  DosagePlaybackMeter meter() => DosagePlaybackMeter(now: () => clock);

  setUp(() => clock = DateTime.utc(2026, 1, 1, 12));

  void advance(Duration d) => clock = clock.add(d);

  test('accumulates only the time the player reported PLAYING', () {
    final m = meter();
    m.setPlaying(true);
    advance(const Duration(seconds: 4));
    expect(m.finish(), const Duration(seconds: 4));
  });

  test('a pause banks nothing — only what was actually heard counts', () {
    final m = meter();
    m.setPlaying(true);
    advance(const Duration(seconds: 3));
    m.setPlaying(false);
    // The learner walked away with the message paused. None of this is
    // listening, and counting it would make the counter a measure of how long a
    // widget was on screen.
    advance(const Duration(minutes: 10));
    m.setPlaying(true);
    advance(const Duration(seconds: 2));
    expect(
      m.finish(),
      const Duration(seconds: 5),
      reason: 'the 10 idle minutes between the two plays are not listening',
    );
  });

  test('repeated same-state events neither restart nor double-count', () {
    // playerStateStream re-emits on every buffering and position change, so the
    // meter sees the same `playing: true` many times per playback.
    final m = meter();
    m.setPlaying(true);
    advance(const Duration(seconds: 2));
    m.setPlaying(true);
    m.setPlaying(true);
    advance(const Duration(seconds: 2));
    m.setPlaying(false);
    m.setPlaying(false);
    expect(m.finish(), const Duration(seconds: 4));
  });

  test('playback that never started measures NOTHING, not zero', () {
    // The category-2 silent exit: no known-good device voice and the backend
    // disallowed, so tryToSpeak returns near-instantly having played nothing.
    // The caller must be able to tell that apart from a real 0 ms play, because
    // one is a non-event and the other is an observation.
    final m = meter();
    expect(m.hasStarted, isFalse);
    expect(m.finish(), isNull);
  });

  test('finish RESETS, so one playback can never be emitted twice', () {
    // Completion closes the measurement; dispose closes it again moments later.
    // Both call finish, and only the first may yield a magnitude.
    final m = meter();
    m.setPlaying(true);
    advance(const Duration(seconds: 6));
    expect(m.finish(), const Duration(seconds: 6));
    expect(
      m.finish(),
      isNull,
      reason: 'a second close after the same playback emits nothing',
    );
  });

  test('a backwards clock jump can never produce a negative magnitude', () {
    // Wall time, not a monotonic source: an NTP correction or a timezone change
    // mid-playback can move it backwards.
    final m = meter();
    m.setPlaying(true);
    clock = clock.subtract(const Duration(hours: 2));
    expect(m.finish(), isNull, reason: 'nothing measured, not a negative');
  });

  test('a forward clock jump is capped at the event ceiling', () {
    final m = meter();
    m.setPlaying(true);
    clock = clock.add(const Duration(days: 3));
    expect(
      m.finish()!.inMilliseconds,
      DosageAudioEvent.maxElapsedMs,
      reason: 'a suspended device cannot report three days of listening',
    );
  });

  test('elapsed reads the in-flight interval without closing it', () {
    final m = meter();
    m.setPlaying(true);
    advance(const Duration(seconds: 3));
    expect(m.elapsed, const Duration(seconds: 3));
    expect(m.isRunning, isTrue);
    advance(const Duration(seconds: 1));
    expect(m.finish(), const Duration(seconds: 4));
  });
}
