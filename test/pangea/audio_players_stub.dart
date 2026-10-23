import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

/// Pressable buttons build an audioplayers player for their click sound,
/// which has no platform in a widget test. Its channels carry a per-player
/// id, so they are answered by prefix; every other channel keeps its own mock
/// handler.
class AudioPlayersStub {
  static void install() {
    TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .allMessagesHandler = (channel, handler, message) =>
        channel.startsWith('xyz.luan/audioplayers')
        ? Future.value(const StandardMethodCodec().encodeSuccessEnvelope(null))
        : handler?.call(message);
  }

  static void uninstall() {
    TestDefaultBinaryMessengerBinding
            .instance
            .defaultBinaryMessenger
            .allMessagesHandler =
        null;
  }
}
