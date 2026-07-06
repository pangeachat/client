import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_block.dart';

void main() {
  group('ActivityMediaBlock youtube poster', () {
    ActivityMediaBlock yt(String url, {String? thumbnailUrl}) =>
        ActivityMediaBlock(
          blockType: 'youtube',
          url: url,
          thumbnailUrl: thumbnailUrl,
        );

    test('parses the 11-char id from watch / youtu.be / embed / shorts urls', () {
      const id = 'dQw4w9WgXcQ';
      expect(yt('https://www.youtube.com/watch?v=$id').youtubeId, id);
      expect(yt('https://youtu.be/$id').youtubeId, id);
      expect(yt('https://www.youtube.com/embed/$id').youtubeId, id);
      expect(yt('https://www.youtube.com/shorts/$id').youtubeId, id);
      // Extra query params around v= still resolve.
      expect(
        yt('https://www.youtube.com/watch?list=abc&v=$id&t=3s').youtubeId,
        id,
      );
    });

    test('derives a 16:9 mqdefault poster (no baked-in letterbox bars)', () {
      final block = yt('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(
        block.youtubeThumbnailUrl,
        'https://img.youtube.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
      );
      // Guard against a regression to any of the 4:3 (letterboxed) variants.
      expect(block.youtubeThumbnailUrl, isNot(contains('hqdefault')));
      expect(block.youtubeThumbnailUrl, isNot(contains('sddefault')));
      expect(
        block.youtubeThumbnailUrl,
        isNot(endsWith('/default.jpg')),
      );
    });

    test('displayUrl prefers an explicit thumbnailUrl over the derived poster',
        () {
      final block = yt(
        'https://youtu.be/dQw4w9WgXcQ',
        thumbnailUrl: 'https://content.pangea.chat/custom-poster.jpg',
      );
      expect(block.displayUrl(256), 'https://content.pangea.chat/custom-poster.jpg');
    });

    test('displayUrl falls back to the derived poster when no thumbnailUrl', () {
      final block = yt('https://youtu.be/dQw4w9WgXcQ');
      expect(
        block.displayUrl(256),
        'https://img.youtube.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
      );
    });

    test('unparseable youtube url yields no derived poster', () {
      final block = yt('https://example.com/not-a-video');
      expect(block.youtubeId, isNull);
      expect(block.youtubeThumbnailUrl, isNull);
      expect(block.displayUrl(256), isNull);
    });
  });
}
