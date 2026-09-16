import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/client_download_content_extension.dart';
import 'get_test_client.dart';

/// Course rooms carry https avatars from the assets bucket — a supported shape
/// that `Avatar` renders through `ImageByUrl`. Notification surfaces have no
/// such fallback, and the SDK answers anything but an `mxc` scheme with an
/// empty `Uri()`, which reaches `httpClient.get` as a hostless URL and throws
/// (CLIENT-A20). They must render without an avatar instead.
void main() {
  late Client client;

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  const templateAvatar =
      'https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Space%20template%203.png';

  group('canDownloadMxc', () {
    test('an mxc avatar is downloadable', () {
      expect(client.canDownloadMxc(Uri.parse('mxc://example.org/abc')), isTrue);
    });

    test('an https avatar is not', () {
      expect(client.canDownloadMxc(Uri.parse(templateAvatar)), isFalse);
    });

    test('an absent avatar is not', () {
      expect(client.canDownloadMxc(null), isFalse);
    });

    test('nothing is downloadable without a homeserver', () {
      client.homeserver = null;
      expect(
        client.canDownloadMxc(Uri.parse('mxc://example.org/abc')),
        isFalse,
        reason: 'the SDK returns the same empty Uri() sentinel in this case',
      );
    });
  });

  group('downloadAvatarCached', () {
    test('an https avatar yields no avatar rather than throwing', () {
      expect(
        client.downloadAvatarCached(
          Uri.parse(templateAvatar),
          width: 128,
          height: 128,
          isThumbnail: true,
          thumbnailMethod: ThumbnailMethod.crop,
        ),
        completion(isNull),
      );
    });

    test('an absent avatar yields no avatar', () {
      expect(
        client.downloadAvatarCached(
          null,
          width: 128,
          height: 128,
          isThumbnail: true,
          thumbnailMethod: ThumbnailMethod.crop,
        ),
        completion(isNull),
      );
    });

    test('the unguarded download is what throws on the same avatar', () {
      expect(
        client.downloadMxcCached(
          Uri.parse(templateAvatar),
          width: 128,
          height: 128,
          isThumbnail: true,
          thumbnailMethod: ThumbnailMethod.crop,
        ),
        throwsA(anything),
        reason:
            'the guard exists because of this; the type varies with the http '
            'stack, so only the throw itself is asserted',
      );
    });
  });
}
