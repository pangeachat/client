import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_block.dart';
import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

void main() {
  ActivityPlanRequest req() => ActivityPlanRequest(
    topic: 'jobs',
    mode: 'Roleplay',
    objective: 'introduce yourself',
    media: MediaEnum.nan,
    cefrLevel: LanguageLevelTypeEnum.a1,
    languageOfInstructions: 'en',
    targetLanguage: 'de',
    numberOfParticipants: 2,
  );

  ActivityPlanModel plan(List<ActivityMediaBlock> media, {String? imageURL}) =>
      ActivityPlanModel(
        req: req(),
        title: 'Speed-Dating Interview',
        learningObjective: 'lo',
        instructions: 'i',
        vocab: const [],
        activityId: 'act-1',
        imageURL: imageURL,
        media: media,
      );

  ActivityMediaBlock youtube(String url) =>
      ActivityMediaBlock(blockType: 'youtube', url: url);
  ActivityMediaBlock image(String resolvedUrl) =>
      ActivityMediaBlock(blockType: 'image', resolvedUrl: resolvedUrl);
  ActivityMediaBlock audio(String resolvedUrl) =>
      ActivityMediaBlock(blockType: 'audio', resolvedUrl: resolvedUrl);

  group('ActivityPlanModel start-page hero', () {
    test('a youtube lead leads with the video poster, not the placeholder', () {
      final p = plan([youtube('https://youtu.be/dQw4w9WgXcQ')]);
      expect(p.visibleHeroBlock?.isYoutube, isTrue);
      expect(p.heroIsPlayable, isTrue);
      expect(
        p.heroDisplayUrl.toString(),
        'https://img.youtube.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
      );
    });

    test('an image lead is not playable and shows the image', () {
      final p = plan([image('https://content.pangea.chat/hero.jpg')]);
      expect(p.heroIsPlayable, isFalse);
      expect(
        p.heroDisplayUrl.toString(),
        'https://content.pangea.chat/hero.jpg',
      );
    });

    test('skips a non-visual audio lead to the first visible block', () {
      final p = plan([
        audio('https://content.pangea.chat/clip.mp3'),
        youtube('https://youtu.be/dQw4w9WgXcQ'),
      ]);
      expect(p.visibleHeroBlock?.isYoutube, isTrue);
      expect(p.heroIsPlayable, isTrue);
      expect(
        p.heroDisplayUrl.toString(),
        'https://img.youtube.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
      );
    });

    test('no media falls back to the legacy image url', () {
      final p = plan(
        const [],
        imageURL: 'https://content.pangea.chat/legacy.png',
      );
      expect(p.visibleHeroBlock, isNull);
      expect(p.heroIsPlayable, isFalse);
      expect(p.heroDisplayUrl.toString(), contains('legacy.png'));
    });

    test(
      'no media and no image url yields a deterministic placeholder, never null',
      () {
        final p = plan(const []);
        expect(p.heroIsPlayable, isFalse);
        expect(p.heroDisplayUrl, isNotNull);
        // A real placeholder asset, not a broken/absent poster.
        expect(p.heroDisplayUrl.toString(), contains('Space%20template'));
      },
    );
  });
}
