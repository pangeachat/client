import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'package:fluffychat/routes/chat/activity_sessions/activity_youtube_player.dart';

void main() {
  group('activity YouTube captions', () {
    test(
      'narrows an activity language to the two-letter cc_lang_pref code',
      () {
        expect(ActivityYoutubePlayer.captionLanguageCode('es'), 'es');
        expect(ActivityYoutubePlayer.captionLanguageCode('EN'), 'en');
        // Localized codes: a caption track is a language, not a script variant.
        expect(ActivityYoutubePlayer.captionLanguageCode('zh-Hans'), 'zh');
        expect(ActivityYoutubePlayer.captionLanguageCode('pt-BR'), 'pt');
      },
    );

    test('leaves the preference unset when the language is unusable', () {
      // Unset beats the package default, which would name English (#8828).
      expect(ActivityYoutubePlayer.captionLanguageCode(null), isNull);
      expect(ActivityYoutubePlayer.captionLanguageCode(''), isNull);
      expect(ActivityYoutubePlayer.captionLanguageCode('  '), isNull);
    });

    test(
      'the package default we are overriding forces captions on, in English',
      () {
        // Guards the reason this plumbing exists: with no params of our own,
        // every activity video would force captions on and ask for English
        // whatever the activity's language is.
        const defaults = YoutubePlayerParams();
        expect(defaults.enableCaption, isTrue);
        expect(defaults.captionLanguage, 'en');
      },
    );
  });
}
