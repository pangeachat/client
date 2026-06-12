import 'dart:math';

import 'package:fluffychat/config/app_config.dart';

abstract class AvatarProvider {
  Uri getRandomAvatarUrl();
}

class RandomAvatarProvider implements AvatarProvider {
  String _avatarUrlString(int index) =>
      "${AppConfig.assetsBaseURL}/avatar_$index.png";

  @override
  Uri getRandomAvatarUrl() {
    final Random random = Random();
    return Uri.parse(_avatarUrlString(random.nextInt(4) + 1));
  }
}

class MockAvatarProvider implements AvatarProvider {
  @override
  Uri getRandomAvatarUrl() => Uri.parse(
    "https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/avatar_5.png",
  );
}
