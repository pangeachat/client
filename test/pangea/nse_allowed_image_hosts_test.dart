import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';

void main() {
  // The iOS notification service extension resolves avatars in its own process
  // and is handed this set through the App Group container. It fails closed, so
  // an empty or narrowed list silently stops every https avatar from rendering
  // on a notification rather than erroring anywhere visible.
  group('allowedImageHosts feeds the notification extension', () {
    test('exposes the same hosts isAllowedImage accepts', () {
      expect(AppConfig.allowedImageHosts, isNotEmpty);
      for (final host in AppConfig.allowedImageHosts) {
        expect(
          AppConfig.isAllowedImage(Uri.parse('https://$host/avatar.png')),
          isTrue,
          reason:
              '$host is published to the extension but rejected by '
              'isAllowedImage, so the two would disagree',
        );
      }
    });

    test('still covers the hosts avatars are actually served from', () {
      expect(AppConfig.allowedImageHosts, contains('content.pangea.chat'));
      expect(
        AppConfig.allowedImageHosts,
        contains('pangea-chat-client-assets.s3.us-east-1.amazonaws.com'),
      );
    });

    test('rejects a host outside the list', () {
      expect(
        AppConfig.isAllowedImage(Uri.parse('https://evil.example/avatar.png')),
        isFalse,
      );
    });
  });
}
