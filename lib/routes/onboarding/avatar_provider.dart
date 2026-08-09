import 'dart:math';

import 'package:fluffychat/pangea/common/constants/preset_avatars.dart';

abstract class AvatarProvider {
  Uri getRandomAvatarUrl();
}

class RandomAvatarProvider implements AvatarProvider {
  @override
  Uri getRandomAvatarUrl() {
    final Random random = Random();
    return PresetAvatars.url(random.nextInt(PresetAvatars.count) + 1);
  }
}

class MockAvatarProvider implements AvatarProvider {
  @override
  Uri getRandomAvatarUrl() => PresetAvatars.url(5);
}
