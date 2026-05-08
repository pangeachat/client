import 'dart:math';

import 'package:fluffychat/config/app_config.dart';

abstract class RandomAvatarProvider {
  Uri getRandomAvatarUrl();

  List<Uri> get avatarOptions;
}

class UserAvatarProvider extends RandomAvatarProvider {
  String _avatarUrlString(int index) =>
      "${AppConfig.assetsBaseURL}/avatar_$index.png";

  @override
  List<Uri> get avatarOptions =>
      List.generate(5, (index) => Uri.parse(_avatarUrlString(index + 1)));

  @override
  Uri getRandomAvatarUrl() {
    final Random random = Random();
    return Uri.parse(_avatarUrlString(random.nextInt(4) + 1));
  }
}
