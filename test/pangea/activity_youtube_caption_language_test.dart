import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'package:fluffychat/routes/chat/activity_sessions/activity_youtube_player.dart';

void main() {
  group('activity YouTube captions', () {
    test('narrows an activity language to the cc_lang_pref code', () {
      expect(ActivityYoutubePlayer.captionLanguageCode('es'), 'es');
      expect(ActivityYoutubePlayer.captionLanguageCode('EN'), 'en');
      // Localized codes: a caption track is a language, not a script or region
      // variant.
      expect(ActivityYoutubePlayer.captionLanguageCode('zh-Hans'), 'zh');
      expect(ActivityYoutubePlayer.captionLanguageCode('pt-BR'), 'pt');
      expect(ActivityYoutubePlayer.captionLanguageCode('en_US'), 'en');
      // Three-letter languages we teach have YouTube caption tracks of their
      // own; narrowing them to two letters would lose the preference.
      expect(ActivityYoutubePlayer.captionLanguageCode('haw'), 'haw');
      expect(ActivityYoutubePlayer.captionLanguageCode('fil'), 'fil');
    });

    test('leaves the preference unset when the language is unusable', () {
      // Unset beats the package default, which would name English (#8828).
      expect(ActivityYoutubePlayer.captionLanguageCode(null), isNull);
      expect(ActivityYoutubePlayer.captionLanguageCode(''), isNull);
      expect(ActivityYoutubePlayer.captionLanguageCode('  '), isNull);
      // Anything that isn't a bare language code is dropped rather than sent
      // as a bogus cc_lang_pref.
      expect(ActivityYoutubePlayer.captionLanguageCode('english'), isNull);
      expect(ActivityYoutubePlayer.captionLanguageCode('123'), isNull);
      expect(ActivityYoutubePlayer.captionLanguageCode('e'), isNull);
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
