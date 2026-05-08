import 'package:fluffychat/pangea/onboarding/random_avatar_provider.dart';

class MockAvatarProvider extends RandomAvatarProvider {
  @override
  List<Uri> get avatarOptions => [
    Uri.parse(
      "https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/avatar_5.png",
    ),
  ];

  @override
  Uri getRandomAvatarUrl() => Uri.parse(
    "https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/avatar_5.png",
  );
}
