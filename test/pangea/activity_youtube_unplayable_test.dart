import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'package:fluffychat/routes/chat/activity_sessions/activity_youtube_player.dart';

bool unplayable(
  PlayerState state, {
  YoutubeError error = YoutubeError.none,
  bool everPlayed = false,
  bool waitedOut = false,
}) => ActivityYoutubePlayer.isUnplayable(
  YoutubePlayerValue(playerState: state, error: error),
  everPlayed: everPlayed,
  waitedOut: waitedOut,
);

void main() {
  group('activity YouTube player offers YouTube instead (#9244)', () {
    test('as soon as YouTube refuses the video', () {
      // 150 is what Khue's iPhone got for two embeddable videos.
      expect(
        unplayable(
          PlayerState.unStarted,
          error: YoutubeError.sameAsNotEmbeddable,
        ),
        isTrue,
      );
      expect(
        unplayable(PlayerState.unknown, error: YoutubeError.notEmbeddable),
        isTrue,
      );
    });

    test('not while it is still within the wait', () {
      expect(unplayable(PlayerState.unknown), isFalse);
      expect(unplayable(PlayerState.unStarted), isFalse);
    });

    test('after the wait, when it has neither played nor started loading', () {
      expect(unplayable(PlayerState.unknown, waitedOut: true), isTrue);
      expect(unplayable(PlayerState.unStarted, waitedOut: true), isTrue);
    });

    test('not after the wait when it is loading or has played', () {
      // A slow network, not a refusal.
      expect(unplayable(PlayerState.buffering, waitedOut: true), isFalse);
      // Played, then paused by the learner.
      expect(
        unplayable(PlayerState.paused, everPlayed: true, waitedOut: true),
        isFalse,
      );
    });
  });
}
